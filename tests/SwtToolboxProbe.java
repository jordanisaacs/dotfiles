import java.lang.instrument.Instrumentation;
import java.lang.reflect.Method;
import java.net.URL;
import java.nio.file.Files;
import java.nio.file.Path;

/** Test-only inspection of Toolbox's actual OSGi-loaded SWT and browser service. */
public final class SwtToolboxProbe {
    private SwtToolboxProbe() {}

    private static Class<?> loaded(Instrumentation instrumentation, String name) {
        for (Class<?> type : instrumentation.getAllLoadedClasses()) {
            if (type.getName().equals(name)) return type;
        }
        return null;
    }

    public static void premain(String output, Instrumentation instrumentation) {
        Thread worker = new Thread(() -> {
            try {
                for (int attempt = 0; attempt < 600; attempt++) {
                    Class<?> displayClass = loaded(instrumentation,
                        "org.eclipse.swt.widgets.Display");
                    // Do not initialize SWT from this worker. Wait for Toolbox
                    // itself to have constructed its normal welcome UI.
                    Class<?> intro = loaded(instrumentation,
                        "org.lamport.tla.toolbox.ui.intro.ToolboxIntroPart");
                    if (displayClass != null && intro != null) {
                        for (Thread thread : Thread.getAllStackTraces().keySet()) {
                            Object display = displayClass.getMethod("findDisplay", Thread.class)
                                .invoke(null, thread);
                            if (display != null) {
                                Class<?> type = displayClass;
                                displayClass.getMethod("asyncExec", Runnable.class).invoke(display,
                                    (Runnable) () -> createProbe(type, display, output, instrumentation));
                                return;
                            }
                        }
                    }
                    Thread.sleep(100);
                }
                throw new IllegalStateException("Toolbox did not create a native display");
            } catch (Exception exception) {
                exception.printStackTrace();
                System.exit(43);
            }
        }, "toolbox-regression-probe");
        worker.setDaemon(true);
        worker.start();
    }

    private static void createProbe(Class<?> displayClass, Object display, String output,
                                    Instrumentation instrumentation) {
        try {
            ClassLoader loader = displayClass.getClassLoader();
            Class<?> shellClass = Class.forName("org.eclipse.swt.widgets.Shell", true, loader);
            Class<?> composite = Class.forName("org.eclipse.swt.widgets.Composite", true, loader);
            Class<?> labelClass = Class.forName("org.eclipse.swt.widgets.Label", true, loader);
            Object shell = shellClass.getConstructor(displayClass).newInstance(display);
            shellClass.getMethod("setText", String.class).invoke(shell, "Toolbox rendering test");
            Object label = labelClass.getConstructor(composite, int.class).newInstance(shell, 0);
            labelClass.getMethod("setText", String.class).invoke(label,
                "A Toolbox label must contain its font");
            labelClass.getMethod("pack").invoke(label);
            shellClass.getMethod("pack").invoke(shell);
            shellClass.getMethod("open").invoke(shell);
            displayClass.getMethod("timerExec", int.class, Runnable.class).invoke(display, 500,
                (Runnable) () -> inspect(labelClass, label, loader, output, instrumentation));
        } catch (Exception exception) {
            exception.printStackTrace();
            System.exit(43);
        }
    }

    private static void inspect(Class<?> labelClass, Object label, ClassLoader loader,
                                String output, Instrumentation instrumentation) {
        try {
            Class<?> drawable = Class.forName("org.eclipse.swt.graphics.Drawable", true, loader);
            Class<?> gcClass = Class.forName("org.eclipse.swt.graphics.GC", true, loader);
            Object gc = gcClass.getConstructor(drawable).newInstance(label);
            Object metrics = gcClass.getMethod("getFontMetrics").invoke(gc);
            int fontHeight = ((Number) metrics.getClass().getMethod("getHeight").invoke(metrics))
                .intValue();
            Object size = labelClass.getMethod("getSize").invoke(label);
            int labelHeight = size.getClass().getField("y").getInt(size);
            gcClass.getMethod("dispose").invoke(gc);

            Class<?> program = Class.forName("org.eclipse.swt.program.Program", true, loader);
            System.out.println("SWT_SOURCE " + program.getProtectionDomain().getCodeSource());
            System.out.println("SWT_HTML " + program.getMethod("findProgram", String.class).invoke(null, "html"));
            Class<?> platform = loaded(instrumentation, "org.eclipse.core.runtime.Platform");
            Object bundle = platform.getMethod("getBundle", String.class)
                .invoke(null, "org.eclipse.ui.browser");
            Class<?> managerClass = (Class<?>) bundle.getClass()
                .getMethod("loadClass", String.class)
                .invoke(bundle, "org.eclipse.ui.internal.browser.BrowserManager");
            Object manager = managerClass.getMethod("getInstance").invoke(null);
            Object browser = managerClass.getMethod("getCurrentWebBrowser").invoke(manager);
            boolean systemBrowser = browser != null && browser.getClass().getName()
                .equals("org.eclipse.ui.internal.browser.SystemBrowserDescriptor");

            // The VM registers a private marker browser for this URI. Exercise
            // Eclipse's external-browser API, not a direct xdg-open subprocess.
            String url = System.getProperty("toolbox.test.url");
            if (systemBrowser && url != null) {
                Class<?> platformUi = loaded(instrumentation, "org.eclipse.ui.PlatformUI");
                Object workbench = platformUi.getMethod("getWorkbench").invoke(null);
                Object support = workbench.getClass().getMethod("getBrowserSupport")
                    .invoke(workbench);
                Object external = support.getClass().getMethod("getExternalBrowser")
                    .invoke(support);
                Method open = external.getClass().getMethod("openURL", URL.class);
                open.invoke(external, new URL(url));
            }
            String report = "{\"fontHeight\":" + fontHeight
                + ",\"labelHeight\":" + labelHeight
                + ",\"systemBrowser\":" + systemBrowser + "}";
            Files.writeString(Path.of(output), report);
            System.out.println("TOOLBOX_REGRESSION " + report);
            // This process uses a disposable workspace and never edits a spec.
            System.exit(0);
        } catch (Exception exception) {
            exception.printStackTrace();
            System.exit(43);
        }
    }
}
