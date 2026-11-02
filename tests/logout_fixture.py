#!/usr/bin/env python3
"""A private GUI application whose native close request needs user consent."""

import json
import os
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk


class Fixture(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="dev.snowytrees.LogoutFixture")
        self.window = None
        self.dialog = None
        self.entry = None
        self.close_requests = 0
        self.key_presses = 0
        self.state = Path(os.environ["XDG_RUNTIME_DIR"]) / "logout-fixture.json"
        for name in ("cancel-close", "save-and-close"):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", self.action, name)
            self.add_action(action)

    def write(self):
        self.state.write_text(
            json.dumps(
                {
                    "close_requests": self.close_requests,
                    "key_presses": self.key_presses,
                    "dialog": self.dialog is not None,
                    "pid": os.getpid(),
                    "text": self.entry.get_text() if self.entry else "",
                }
            )
        )

    def do_activate(self):
        if self.window:
            self.window.present()
            return
        self.window = Gtk.ApplicationWindow(application=self)
        self.window.set_title("Unsaved regression document")
        self.window.set_default_size(460, 240)
        self.window.connect("delete-event", self.close_request)
        self.window.connect("key-press-event", self.key)
        entry = Gtk.Entry()
        entry.set_text("Unsaved regression content")
        self.entry = entry
        entry.connect("changed", lambda _entry: self.write())
        self.window.add(entry)
        self.window.show_all()
        entry.grab_focus()
        self.write()

    def key(self, *_arguments):
        self.key_presses += 1
        self.write()
        return False

    def close_request(self, *_arguments):
        self.close_requests += 1
        if not self.dialog:
            self.dialog = Gtk.MessageDialog(
                transient_for=self.window,
                modal=True,
                message_type=Gtk.MessageType.QUESTION,
                text="Save the regression document before closing?",
            )
            self.dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
            self.dialog.add_button("Save and close", Gtk.ResponseType.OK)
            self.dialog.set_default_response(Gtk.ResponseType.CANCEL)
            self.dialog.connect("response", self.response)
            self.dialog.show_all()
        self.write()
        return True

    def response(self, _dialog, response):
        if self.dialog:
            self.dialog.destroy()
            self.dialog = None
        if response == Gtk.ResponseType.OK:
            self.window.destroy()
            self.quit()
        else:
            self.window.present()
        self.write()

    def action(self, _action, _parameter, name):
        if self.dialog:
            self.response(
                self.dialog,
                Gtk.ResponseType.OK
                if name == "save-and-close"
                else Gtk.ResponseType.CANCEL,
            )


if __name__ == "__main__":
    GLib.set_prgname("dev.snowytrees.LogoutFixture")
    raise SystemExit(Fixture().run())
