#include <QApplication>
#include <QColor>
#include <QEventLoop>
#include <QFontDatabase>
#include <QFontInfo>
#include <QFontMetricsF>
#include <QLabel>
#include <QLineEdit>
#include <QMainWindow>
#include <QPalette>
#include <QPushButton>
#include <QStandardItemModel>
#include <QStyle>
#include <QTabWidget>
#include <QTimer>
#include <QTreeView>
#include <QVBoxLayout>
#include <KColorScheme>
#include <KColorSchemeManager>
#include <KSharedConfig>
#include <cmath>
#include <iostream>
#include <utility>

static double luminance(const QColor &color)
{
    const auto linear = [](double value) {
        return value <= 0.04045 ? value / 12.92 : std::pow((value + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * linear(color.redF()) + 0.7152 * linear(color.greenF()) + 0.0722 * linear(color.blueF());
}

static bool checkPalette(const char *name, const QPalette &palette)
{
    for (const auto &[textRole, backgroundRole] : {
             std::pair{QPalette::WindowText, QPalette::Window},
             std::pair{QPalette::Text, QPalette::Base},
             std::pair{QPalette::ButtonText, QPalette::Button},
             std::pair{QPalette::ToolTipText, QPalette::ToolTipBase}}) {
        const auto text = palette.color(QPalette::Active, textRole);
        const auto background = palette.color(QPalette::Active, backgroundRole);
        const auto textLuminance = luminance(text);
        const auto backgroundLuminance = luminance(background);
        const auto contrast = (textLuminance + 0.05) / (backgroundLuminance + 0.05);
        std::cout << name << " text " << text.name().toStdString() << " on "
                  << background.name().toStdString() << ": " << contrast << std::endl;
        if (textLuminance < backgroundLuminance || backgroundLuminance > 0.1 || contrast < 4.5) {
            std::cerr << name << " applications do not have readable dark colors" << std::endl;
            return false;
        }
    }
    return true;
}

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    // Dolphin and other KDE applications initialize this manager. On a
    // non-KDE platform theme it may replace the widget palette independently.
    KColorSchemeManager::instance();
    if (QGuiApplication::platformName() != "wayland") {
        std::cerr << "Test must render on a real Wayland compositor" << std::endl;
        return 1;
    }
    if (app.style()->objectName().compare("kvantum", Qt::CaseInsensitive) != 0) {
        std::cerr << "Configured Kvantum widget style did not load" << std::endl;
        return 1;
    }
    QMainWindow window;
    window.resize(640, 480);
    auto *contents = new QWidget(&window);
    auto *layout = new QVBoxLayout(contents);
    layout->addWidget(new QLabel("Readable application text", contents));
    layout->addWidget(new QLineEdit("Network name", contents));
    layout->addWidget(new QPushButton("Connect", contents));
    auto *tabs = new QTabWidget(contents);
    auto *tree = new QTreeView(tabs);
    auto *model = new QStandardItemModel(tree);
    model->appendRow(new QStandardItem("Readable file name"));
    tree->setModel(model);
    tabs->addTab(tree, "Network and file controls");
    layout->addWidget(tabs);
    window.setCentralWidget(contents);
    window.show();
    QEventLoop settle;
    QTimer::singleShot(500, &settle, &QEventLoop::quit);
    settle.exec();
    const auto kdePalette = KColorScheme::createApplicationPalette(KSharedConfig::openConfig("kdeglobals"));
    bool valid = checkPalette("KDE", kdePalette) && checkPalette("Qt after showing widgets", app.palette());
    for (const auto *widget : window.findChildren<QWidget *>())
        valid = checkPalette(widget->metaObject()->className(), widget->palette()) && valid;
    const auto expectedFont = qEnvironmentVariable("DESKTOP_FONT_POINTS").toDouble();
    if (std::abs(app.font().pointSizeF() - expectedFont) > 0.01) {
        std::cerr << "Qt application font is " << app.font().pointSizeF()
                  << "pt, expected " << expectedFont << "pt" << std::endl;
        valid = false;
    }
    const QFontInfo uiFont(app.font());
    const auto expectedFamily = qEnvironmentVariable("DESKTOP_FONT_FAMILY");
    if (uiFont.family() != expectedFamily) {
        std::cerr << "Qt resolved UI family " << uiFont.family().toStdString()
                  << ", expected " << expectedFamily.toStdString() << std::endl;
        valid = false;
    }
    const QFontMetricsF uiMetrics(app.font());
    const QFontMetricsF fixedMetrics(QFontDatabase::systemFont(QFontDatabase::FixedFont));
    if (uiMetrics.horizontalAdvance("iiii") >= uiMetrics.horizontalAdvance("WWWW") * 0.75
        || std::abs(fixedMetrics.horizontalAdvance("iiii") - fixedMetrics.horizontalAdvance("WWWW")) > 0.1) {
        std::cerr << "UI and fixed-width font roles were not kept separate" << std::endl;
        valid = false;
    }
    if (window.testAttribute(Qt::WA_TranslucentBackground) || window.windowOpacity() < 1.0) {
        std::cerr << "Qt window is translucent" << std::endl;
        valid = false;
    }
    auto image = window.grab().toImage();
    image.save(qEnvironmentVariable("DESKTOP_SCREENSHOT"));
    // Check an interior corner, away from shadows and rounded window edges.
    if (image.pixelColor(20, 20).alpha() != 255) {
        std::cerr << "Rendered Qt window background has alpha "
                  << image.pixelColor(20, 20).alpha() << std::endl;
        valid = false;
    }
    return valid ? 0 : 1;
}
