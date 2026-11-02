"""Exercise native GTK4 CSS loading and shared font settings."""

import json

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib, Gtk


def activate(application):
    window = Adw.ApplicationWindow(application=application)
    window.set_default_size(400, 200)
    window.set_content(Gtk.Label(label="Desktop theme check"))
    window.present()

    def report():
        print(
            json.dumps(
                {
                    "font": Gtk.Settings.get_default().get_property("gtk-font-name"),
                }
            ),
            flush=True,
        )
        application.quit()
        return GLib.SOURCE_REMOVE

    GLib.timeout_add(300, report)


application = Adw.Application(
    application_id="dev.snowytrees.ThemeProbe",
    flags=Gio.ApplicationFlags.NON_UNIQUE,
)
application.connect("activate", activate)
raise SystemExit(application.run([]))
