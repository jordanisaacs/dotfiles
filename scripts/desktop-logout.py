"""Confirm logout, request normal app closure, and keep pending apps visible."""

import concurrent.futures
import json
import re
import subprocess
import sys
import threading
from dataclasses import dataclass

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk


@dataclass(frozen=True, slots=True)
class Window:
    identifier: str
    title: str
    app_id: str


def run(arguments):
    try:
        return subprocess.run(
            arguments, check=True, capture_output=True, text=True, timeout=3
        ).stdout
    except subprocess.CalledProcessError as error:
        raise RuntimeError(
            error.stderr.strip() or error.stdout.strip() or "Desktop command failed"
        ) from error


class Backend:
    def manager(self):
        for name in ("oxbow", "reka"):
            result = subprocess.run(
                [
                    CONFIG["systemctl"],
                    "--user",
                    "is-active",
                    "--quiet",
                    f"river-wm-{name}.service",
                ],
                check=False,
                capture_output=True,
                timeout=3,
            )
            if result.returncode == 0:
                return name
            if result.returncode not in (3, 4):
                raise RuntimeError("Could not read the active desktop session")
        raise RuntimeError("There is no active managed River session")

    def emacs(self, expression):
        return run(
            [CONFIG["emacsclient"], "--socket-name", "reka", "--eval", expression]
        )

    def windows(self):
        if self.manager() == "oxbow":
            values = json.loads(run([CONFIG["oxctl"], "window", "list", "--json"]))
        else:
            # emacsclient prints a Lisp string containing the serialized JSON.
            values = json.loads(json.loads(self.emacs("(jd-reka-logout-inventory)")))
        result = []
        for value in values:
            app_id = value.get("app_id") or ""
            if app_id == CONFIG["applicationId"]:
                continue
            identifier = value.get("identifier")
            if not identifier:
                raise RuntimeError("Application window information is not ready")
            result.append(
                Window(identifier, value.get("title") or "Untitled window", app_id)
            )
        return result

    def close(self, window):
        if self.manager() == "oxbow":
            run(
                [
                    CONFIG["oxctl"],
                    "window",
                    "close",
                    "--identifier=^" + re.escape(window.identifier) + "$",
                ]
            )
        else:
            self.emacs("(jd-reka-logout-close " + json.dumps(window.identifier) + ")")


class Logout(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=CONFIG["applicationId"])
        self.backend = Backend()
        self.executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        self.cancelled = threading.Event()
        self.phase = "checking"
        self.windows = []
        self.query_pending = False
        self.alive = True
        self.window = None
        self.rendered_state = None
        self.health = {}
        self.health_process = None
        self.health_listing_state = None
        for name in (
            "confirm",
            "cancel",
            "wait",
            "force",
            "force-confirm",
            "force-cancel",
        ):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", self.action, name)
            self.add_action(action)
        self.set_accels_for_action("app.cancel", ["Escape"])

    def do_activate(self):
        if self.window:
            self.window.present()
            return
        self.window = Gtk.ApplicationWindow(application=self)
        self.window.set_title("Log out")
        self.window.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        self.window.set_default_size(520, 360)
        self.window.set_resizable(False)
        self.window.connect("delete-event", self.cancel)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16, margin=24)
        self.window.add(box)
        self.heading = Gtk.Label(xalign=0)
        self.heading.set_line_wrap(True)
        box.pack_start(self.heading, False, False, 0)
        self.explanation = Gtk.Label(xalign=0)
        self.explanation.set_line_wrap(True)
        box.pack_start(self.explanation, False, False, 0)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_min_content_height(150)
        self.listing = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        scroll.add(self.listing)
        box.pack_start(scroll, True, True, 0)
        self.buttons = Gtk.ButtonBox(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.buttons.set_layout(Gtk.ButtonBoxStyle.END)
        box.pack_end(self.buttons, False, False, 0)
        self.render()
        self.window.show_all()
        self.start_health()
        GLib.timeout_add(500, self.refresh)
        self.refresh()

    def button(self, label, action, *, default=False, destructive=False):
        button = Gtk.Button.new_with_mnemonic(label)
        button.set_action_name("app." + action)
        if destructive:
            button.get_style_context().add_class("destructive-action")
        button.set_can_default(True)
        self.buttons.add(button)
        if default:
            button.grab_default()
            button.grab_focus()

    def render(self):
        if not self.alive:
            return
        state = (self.phase, tuple(self.windows))
        if state == self.rendered_state:
            return
        self.rendered_state = state
        for child in self.buttons.get_children():
            self.buttons.remove(child)
        self.render_listing()
        count = len(self.windows)
        quantity = f"{count} application {'window' if count == 1 else 'windows'}"
        if self.phase == "checking":
            self.heading.set_text("Checking open applications…")
            self.explanation.set_text(
                "Your applications will stay open until you confirm."
            )
            self.button("_Cancel", "cancel", default=True)
        elif self.phase == "confirm":
            self.heading.set_text("Close applications and log out?")
            self.explanation.set_text(
                quantity + " are open. Applications can ask you to save work. "
                "Canceling logout will not reopen applications already closed."
            )
            self.button("Close applications and _log out", "confirm")
            self.button("_Cancel", "cancel", default=True)
        elif self.phase == "force":
            self.heading.set_text("Force quit remaining applications and log out?")
            self.explanation.set_text(
                "Unsaved work in the remaining applications may be lost. "
                "This ends the desktop session and stops its applications."
            )
            self.button("_Force quit and log out", "force-confirm", destructive=True)
            self.button("_Keep waiting", "force-cancel", default=True)
        elif self.phase == "closing":
            self.heading.set_text("Waiting for " + quantity)
            self.explanation.set_text(
                "Check applications for save dialogs. Logout continues when all windows "
                "are closed. You can cancel logout to keep working."
            )
            self.button("_Force quit…", "force", destructive=True)
            self.button("_Keep waiting", "wait", default=True)
            self.button("_Cancel logout", "cancel")
        else:
            self.heading.set_text("Logging out…")
            self.explanation.set_text("Ending the desktop session.")
        for name, phases in {
            "confirm": ("confirm",),
            "cancel": ("checking", "confirm", "closing", "force"),
            "wait": ("closing",),
            "force": ("closing",),
            "force-confirm": ("force",),
            "force-cancel": ("force",),
        }.items():
            self.lookup_action(name).set_enabled(self.phase in phases)
        self.window.show_all()

    def render_listing(self):
        # Health transitions must not rebuild buttons or steal keyboard focus
        # from Cancel/Keep waiting, including while the force warning is open.
        state = (tuple(self.windows), tuple(sorted(self.health.items())))
        if state == self.health_listing_state:
            return
        self.health_listing_state = state
        for child in self.listing.get_children():
            self.listing.remove(child)
        for window in self.windows:
            row = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
            title = Gtk.Label(label=window.title, xalign=0)
            title.set_line_wrap(True)
            title.set_max_width_chars(60)
            row.pack_start(title, False, False, 0)
            status = self.health.get(window.identifier, ("unknown", None))
            if status[0] == "unresponsive":
                detail = "Not responding"
            elif status[0] == "responsive":
                detail = "Responding"
            elif status[1] == 3:
                detail = "Response monitoring unavailable"
            else:
                detail = "Waiting for app"
            if window.app_id:
                detail = window.app_id + " · " + detail
            label = Gtk.Label(label=detail, xalign=0)
            label.set_line_wrap(True)
            label.get_style_context().add_class("dim-label")
            row.pack_start(label, False, False, 0)
            self.listing.pack_start(row, False, False, 0)
        self.listing.show_all()

    def start_health(self):
        executable = CONFIG.get("health")
        if not executable:
            return
        try:
            process = subprocess.Popen(
                [executable, "--watch"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
        except OSError as error:
            print(f"Application response monitor unavailable: {error}", file=sys.stderr)
            return
        self.health_process = process

        def read():
            # Keep one native observer for the dialog lifetime: reconnecting
            # each refresh would discard the compositor's ping timeout state.
            with process.stdout:
                for line in process.stdout:
                    try:
                        value = json.loads(line)
                        identifier = value["identifier"]
                        status = value["status"]
                        native_state = value["native_state"]
                        if (
                            not isinstance(identifier, str)
                            or status
                            not in ("responsive", "unresponsive", "unknown", "closed")
                            or native_state not in range(5)
                        ):
                            continue
                    except ValueError, TypeError, KeyError:
                        continue
                    GLib.idle_add(self.health_updated, identifier, status, native_state)
            process.wait()
            GLib.idle_add(self.health_ended, process)

        threading.Thread(target=read, name="logout-app-response", daemon=True).start()

    def health_updated(self, identifier, status, native_state):
        if self.alive:
            if status == "closed":
                self.health.pop(identifier, None)
            else:
                self.health[identifier] = (status, native_state)
            self.render_listing()
        return GLib.SOURCE_REMOVE

    def health_ended(self, process):
        if self.health_process is process:
            self.health_process = None
            self.health.clear()
            if self.alive:
                self.render_listing()
        return GLib.SOURCE_REMOVE

    def do_shutdown(self):
        self.alive = False
        self.cancelled.set()
        self.executor.shutdown(wait=False, cancel_futures=True)
        if self.health_process is not None:
            try:
                # This is our observer child, never an application process.
                self.health_process.terminate()
            except ProcessLookupError:
                pass
        Gtk.Application.do_shutdown(self)

    def refresh(self):
        if not self.alive or self.phase == "stopping":
            return GLib.SOURCE_REMOVE
        if not self.query_pending:
            self.query_pending = True
            future = self.executor.submit(self.backend.windows)
            future.add_done_callback(lambda result: GLib.idle_add(self.updated, result))
        return GLib.SOURCE_CONTINUE

    def updated(self, future):
        self.query_pending = False
        if not self.alive:
            return GLib.SOURCE_REMOVE
        try:
            self.windows = future.result()
        except (
            RuntimeError,
            subprocess.SubprocessError,
            OSError,
            ValueError,
            TypeError,
            KeyError,
        ) as error:
            print(f"Cannot inspect application windows: {error}", file=sys.stderr)
            self.rendered_state = None
            self.explanation.set_text(
                "Waiting for application window information. You can cancel logout."
            )
            return GLib.SOURCE_REMOVE
        if self.phase in ("closing", "force") and not self.windows:
            self.stop_session()
        elif self.phase == "checking":
            if self.windows:
                self.phase = "confirm"
                self.render()
            else:
                self.stop_session()
        else:
            self.render()
        return GLib.SOURCE_REMOVE

    def request_close(self, windows):
        for window in windows:
            if self.cancelled.is_set():
                return
            try:
                self.backend.close(window)
            except (
                RuntimeError,
                subprocess.SubprocessError,
                OSError,
                ValueError,
            ) as error:
                print(f"Application close request failed: {error}", file=sys.stderr)

    def action(self, _action, _parameter, name):
        if name == "cancel":
            self.cancel()
        elif name == "confirm":
            self.phase = "closing"
            self.executor.submit(self.request_close, tuple(self.windows))
            self.render()
        elif name == "force":
            self.phase = "force"
            self.render()
        elif name == "force-confirm":
            self.stop_session()
        elif name == "force-cancel":
            self.phase = "closing"
            self.render()
        elif name == "wait":
            self.refresh()

    def stop_session(self):
        self.phase = "stopping"
        self.cancelled.set()
        self.render()
        subprocess.Popen([CONFIG["uwsm"], "stop"], start_new_session=True)

    def cancel(self, *_arguments):
        self.alive = False
        self.cancelled.set()
        self.executor.shutdown(wait=False, cancel_futures=True)
        self.quit()
        return True


if __name__ == "__main__":
    # GTK3's Wayland app-id can use the executable's program name rather
    # than GtkApplication's D-Bus name. Give our own windows a stable identity.
    GLib.set_prgname(CONFIG["applicationId"])
    GLib.set_application_name("Log Out")
    raise SystemExit(Logout().run(sys.argv))
