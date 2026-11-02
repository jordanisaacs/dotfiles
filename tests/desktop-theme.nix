{ pkgs, home }:
let
  configFiles = [
    "kdeglobals"
    "Kvantum/kvantum.kvconfig"
  ]
  ++ builtins.filter (
    name: pkgs.lib.hasPrefix "Kvantum/" name && name != "Kvantum/kvantum.kvconfig"
  ) (builtins.attrNames home.xdg.configFile);
  configRoot = pkgs.linkFarm "desktop-theme-config" (
    map (name: {
      inherit name;
      path = home.xdg.configFile.${name}.source;
    }) configFiles
  );
  paletteCheck = pkgs.stdenv.mkDerivation {
    pname = "desktop-kde-palette-check";
    version = "1";
    src = pkgs.linkFarm "desktop-kde-palette-check-source" [
      {
        name = "main.cpp";
        path = ./desktop-theme.cpp;
      }
      {
        name = "CMakeLists.txt";
        path = pkgs.writeText "CMakeLists.txt" ''
          cmake_minimum_required(VERSION 3.20)
          project(desktop_palette_check LANGUAGES CXX)
          set(CMAKE_CXX_STANDARD 17)
          find_package(Qt6 REQUIRED COMPONENTS Widgets)
          find_package(KF6ColorScheme REQUIRED)
          add_executable(desktop-palette-check main.cpp)
          target_link_libraries(desktop-palette-check Qt6::Widgets KF6::ColorScheme)
          install(TARGETS desktop-palette-check DESTINATION bin)
        '';
      }
    ];
    nativeBuildInputs = [
      pkgs.cmake
      pkgs.kdePackages.wrapQtAppsHook
    ];
    buildInputs = [
      pkgs.kdePackages.qtbase
      pkgs.kdePackages.kcolorscheme
    ];
    dontWrapQtApps = true;
    # KDE's setup hook supplies installation paths unused by this tiny fixture.
    cmakeFlags = [ "-Wno-unused-cli" ];
  };
in
pkgs.runCommand "desktop-theme-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    XDG_CONFIG_HOME = configRoot;
    QT_QPA_PLATFORM = "wayland";
    QT_QPA_PLATFORMTHEME = home.home.sessionVariables.QT_QPA_PLATFORMTHEME;
    QT_STYLE_OVERRIDE = home.home.sessionVariables.QT_STYLE_OVERRIDE;
    QT_PLUGIN_PATH = "${home.home.path}/lib/qt-6/plugins:${pkgs.kdePackages.qtwayland}/lib/qt-6/plugins:${pkgs.kdePackages.kwindowsystem}/lib/qt-6/plugins";
    XDG_DATA_DIRS = "${home.home.path}/share";
    ICON_ROOT = "${home.home.path}/share/icons";
    KDE_PALETTE_CHECK = "${paletteCheck}/bin/desktop-palette-check";
    FIREFOX_USER_JS = home.home.file.".mozilla/firefox/personal/user.js".source;
    FONTCONFIG_FILE = pkgs.makeFontsConf {
      fontDirectories = [
        pkgs.dejavu_fonts
        pkgs.bm-variable-font
        home.gtk.font.package
      ];
    };
    WESTON = "${pkgs.weston}/bin/weston";
    DESKTOP_FONT_POINTS = toString home.gtk.font.size;
    DESKTOP_FONT_FAMILY = home.gtk.font.name;
  }
  ''
    python -B ${./test_desktop_theme.py}
    touch "$out"
  ''
