"""Native GTK context-menu fixture, used only inside the Control+click VM."""

import json
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk

assert Path("/etc/control-click-vm").exists(), "Refusing fixture outside its VM"
GLib.set_prgname("control-click-probe")
events = Path("/tmp/control-click-gtk.jsonl")
window = Gtk.Window(title="Native Control Click Context Menu")
window.set_default_size(640, 480)
box = Gtk.EventBox()
box.set_can_focus(True)
box.add(Gtk.Label(label="Control-click opens this native GTK menu"))
box.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK)
window.add(box)
menu = Gtk.Menu()
menu.append(Gtk.MenuItem(label="Native context menu"))
menu.show_all()


def button(_widget, event):
    with events.open("a") as output:
        output.write(
            json.dumps({"button": event.button, "state": int(event.state)}) + "\n"
        )
    if event.button == 3:
        menu.popup_at_pointer(event)
        Path("/tmp/control-click-native-menu").write_text("visible")
    return False


box.connect("button-press-event", button)
window.connect("destroy", Gtk.main_quit)
window.show_all()
box.grab_focus()
Path("/tmp/control-click-gtk-ready").write_text("ready")
Gtk.main()
