"""Exercise packaged xremap on VM-only uinput and private logind/bridge APIs."""

import copy
import grp
import json
import os
import pwd
import select
import socket
import socketserver
import subprocess
import sys
import time
from contextlib import closing
from pathlib import Path

ROOT = Path("/run/xremap-session-test")
STATE = ROOT / "state.json"
ADDRESS = "unix:path=" + str(ROOT / "bus")
SOCKET = ROOT / "1000/xremap.sock"


def state():
    return json.loads(STATE.read_text())


def wait_until(predicate, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError("Fixture condition timed out")


def logind():
    import dbus
    import dbus.mainloop.glib
    import dbus.service
    from gi.repository import GLib

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    connection = dbus.bus.BusConnection(ADDRESS)
    name = dbus.service.BusName("org.freedesktop.login1", connection)
    interface = "org.freedesktop.login1.Session"

    class Session(dbus.service.Object):
        def __init__(self, identity):
            super().__init__(name, "/org/freedesktop/login1/session/" + identity)
            self.identity = identity

        def properties(self):
            current = state()
            source = current[self.identity]
            properties = {
                "Seat": dbus.Struct(
                    ("seat0", dbus.ObjectPath("/org/freedesktop/login1/seat/seat0")),
                    signature="so",
                ),
                "User": dbus.Struct(
                    (
                        dbus.UInt32(current.get("uid", 1000)),
                        dbus.ObjectPath("/org/freedesktop/login1/user/_1000"),
                    ),
                    signature="uo",
                ),
            }
            for key, value in source.items():
                properties[key] = (
                    dbus.Boolean(value)
                    if isinstance(value, bool)
                    else dbus.String(value)
                )
            return properties

        @dbus.service.method(
            "org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}"
        )
        def GetAll(self, requested):
            assert requested == interface
            if state().get("stall", False):
                time.sleep(2)
            return self.properties()

        @dbus.service.method(
            "org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v"
        )
        def Get(self, requested, key):
            assert requested == interface
            return self.properties()[key]

        @dbus.service.signal("org.freedesktop.DBus.Properties", signature="sa{sv}as")
        def PropertiesChanged(self, requested, changed, invalidated):
            pass

    sessions = {key: Session(key) for key in ("gui", "tty")}

    class Manager(dbus.service.Object):
        @dbus.service.method("org.freedesktop.login1.Manager", out_signature="a(susso)")
        def ListSessions(self):
            return [
                (
                    key,
                    dbus.UInt32(1000),
                    "fixture",
                    "seat0",
                    dbus.ObjectPath("/org/freedesktop/login1/session/" + key),
                )
                for key in sessions
            ]

        @dbus.service.method(
            "org.example.XremapFixture", in_signature="s", out_signature=""
        )
        def Transition(self, reason):
            current = state()
            current["signals"] = False
            if reason == "tty":
                current["gui"]["Active"] = False
                current["tty"]["Active"] = True
            elif reason == "locked":
                current["gui"]["LockedHint"] = True
            elif reason == "owner":
                current["uid"] = 1001
            else:
                raise ValueError(reason)
            temporary = ROOT / "inflight.json"
            temporary.write_text(json.dumps(current))
            temporary.chmod(0o644)
            temporary.replace(STATE)

    manager = Manager(name, "/org/freedesktop/login1")
    previous = state()

    def changes():
        nonlocal previous
        current = state()
        if current != previous and current.get("signals", True):
            for key, obj in sessions.items():
                properties = obj.properties()
                changed = {
                    k: properties[k]
                    for k, value in current[key].items()
                    if value != previous[key].get(k)
                }
                invalidated = list(previous[key].keys() - current[key].keys())
                if changed or invalidated:
                    obj.PropertiesChanged(interface, changed, invalidated)
        previous = current
        (ROOT / "ack").write_text(str(current["version"]))
        return True

    GLib.timeout_add(20, changes)
    (ROOT / "logind-ready").touch()
    GLib.MainLoop().run()
    del manager


def bridge():
    class Request(socketserver.StreamRequestHandler):
        def handle(self):
            assert json.loads(self.rfile.readline()) == "ActiveWindow"
            if transition := state().get("switchDuringReply"):
                import dbus

                connection = dbus.bus.BusConnection(ADDRESS)
                manager = connection.get_object(
                    "org.freedesktop.login1", "/org/freedesktop/login1"
                )
                manager.get_dbus_method("Transition", "org.example.XremapFixture")(
                    transition
                )
            if state().get("partialReply", False):
                for _ in range(20):
                    try:
                        self.wfile.write(b" ")
                        self.wfile.flush()
                    except BrokenPipeError, ConnectionResetError:
                        break
                    time.sleep(0.1)
                return
            response = {
                "ActiveWindow": {"title": "fixture", "wm_class": state()["app"]}
            }
            self.wfile.write(json.dumps(response).encode() + b"\n")

    SOCKET.unlink(missing_ok=True)
    with socketserver.UnixStreamServer(str(SOCKET), Request) as server:
        SOCKET.chmod(0o660)
        server.serve_forever()


def saturated_bridge():
    SOCKET.unlink(missing_ok=True)
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
        listener.bind(str(SOCKET))
        SOCKET.chmod(0o660)
        listener.listen(0)
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as queued:
            queued.connect(str(SOCKET))
            SOCKET.with_name("saturated-ready").touch()
            while True:
                time.sleep(1)


def test():
    from evdev import InputDevice, UInput, ecodes, list_devices

    ROOT.mkdir(mode=0o755)
    SOCKET.parent.mkdir()
    os.chown(
        SOCKET.parent, pwd.getpwnam("xremap").pw_uid, grp.getgrnam("xremap-jd").gr_gid
    )
    SOCKET.parent.chmod(0o2770)
    desktop_user = pwd.getpwnam("jd")
    groups = os.getgrouplist("jd", desktop_user.pw_gid)
    assert grp.getgrnam("input").gr_gid not in groups
    assert grp.getgrnam("uinput").gr_gid not in groups
    base = {
        "gui": {
            "Active": True,
            "Remote": False,
            "LockedHint": False,
            "Type": "wayland",
            "Class": "user",
        },
        "tty": {
            "Active": False,
            "Remote": False,
            "LockedHint": False,
            "Type": "tty",
            "Class": "user",
        },
        "app": "fixture.gui",
        "signals": True,
        "version": 0,
    }
    STATE.write_text(json.dumps(base))
    STATE.chmod(0o644)
    configuration = ROOT / "config.json"
    configuration.write_text(
        json.dumps(
            {
                "keymap": [
                    {
                        "application": {"only": "fixture.gui"},
                        "exact_match": True,
                        "remap": {"Super-c": "Ctrl-c"},
                    }
                ]
            }
        )
    )
    configuration.chmod(0o644)
    children = []
    logs = []

    def start(*arguments, **kwargs):
        log = (ROOT / ("process-" + str(len(logs)) + ".log")).open("w")
        logs.append(log)
        child = subprocess.Popen(
            arguments, stdout=log, stderr=subprocess.STDOUT, **kwargs
        )
        children.append(child)
        return child

    def change(current):
        current["version"] = state()["version"] + 1
        temporary = ROOT / "next.json"
        temporary.write_text(json.dumps(current))
        temporary.chmod(0o644)
        temporary.replace(STATE)
        wait_until(
            lambda: (
                (ROOT / "ack").exists()
                and (ROOT / "ack").read_text() == str(current["version"])
            )
        )
        time.sleep(0.1)

    bus_config = ROOT / "dbus.conf"
    bus_config.write_text(
        "<busconfig><type>system</type><listen>"
        + ADDRESS
        + '</listen><auth>EXTERNAL</auth><policy context="default">'
        '<allow user="*"/><allow own="*"/><allow send_destination="*"/>'
        '<allow receive_sender="*"/></policy></busconfig>'
    )
    bus = start("dbus-daemon", "--nofork", "--config-file=" + str(bus_config))
    wait_until(lambda: (ROOT / "bus").exists())
    service = start(sys.executable, __file__, "logind")
    wait_until(lambda: (ROOT / "logind-ready").exists())

    def start_bridge(mode="bridge"):
        return start(
            sys.executable,
            __file__,
            mode,
            user="jd",
            group="xremap-jd",
            extra_groups=["xremap-jd"],
        )

    bridge_process = start_bridge()
    wait_until(SOCKET.exists)

    def replace_bridge(mode="bridge"):
        nonlocal bridge_process
        bridge_process.terminate()
        bridge_process.wait(timeout=5)
        SOCKET.unlink(missing_ok=True)
        SOCKET.with_name("saturated-ready").unlink(missing_ok=True)
        bridge_process = start_bridge(mode)
        if mode == "saturated":
            wait_until(SOCKET.with_name("saturated-ready").exists)
        else:
            wait_until(SOCKET.exists)

    keys = [ecodes.KEY_LEFTMETA, ecodes.KEY_LEFTCTRL, ecodes.KEY_C]

    try:
        with UInput({ecodes.EV_KEY: keys}, name="xremap-session-keyboard") as keyboard:
            subprocess.run(["udevadm", "settle"], check=True)
            for unit, expect_old_bug in (
                ("xremap-guard-stock", True),
                ("xremap-guard-fixed", False),
            ):
                change(copy.deepcopy(base))
                subprocess.run(["systemctl", "start", unit], check=True)

                def output():
                    return next(
                        (
                            path
                            for path in list_devices()
                            if InputDevice(path).name == "xremap-session-output"
                        ),
                        None,
                    )

                wait_until(output)
                with closing(InputDevice(output())) as receiver:

                    def chord(expected_modifier):
                        while select.select([receiver.fd], [], [], 0)[0]:
                            list(receiver.read())
                        for code, value in [
                            (ecodes.KEY_LEFTMETA, 1),
                            (ecodes.KEY_C, 1),
                            (ecodes.KEY_C, 0),
                            (ecodes.KEY_LEFTMETA, 0),
                        ]:
                            keyboard.write(ecodes.EV_KEY, code, value)
                            keyboard.syn()
                            time.sleep(0.025)
                        pressed = set()
                        seen = []
                        deadline = time.monotonic() + 1
                        while time.monotonic() < deadline:
                            if not select.select([receiver.fd], [], [], 0.1)[0]:
                                if seen:
                                    break
                                continue
                            for event in receiver.read():
                                if event.type != ecodes.EV_KEY:
                                    continue
                                if event.value == 1:
                                    pressed.add(event.code)
                                elif event.value == 0:
                                    pressed.discard(event.code)
                                if event.code == ecodes.KEY_C and event.value == 1:
                                    seen.append(set(pressed))
                        if expected_modifier is None:
                            assert not seen, seen
                            return
                        assert len(seen) == 1, seen
                        assert expected_modifier in seen[0], seen
                        other = (
                            ecodes.KEY_LEFTMETA
                            if expected_modifier == ecodes.KEY_LEFTCTRL
                            else ecodes.KEY_LEFTCTRL
                        )
                        assert other not in seen[0], seen
                        assert not pressed, pressed
                        assert not receiver.active_keys(), receiver.active_keys()

                    time.sleep(0.3)
                    chord(ecodes.KEY_LEFTCTRL)
                    tty = copy.deepcopy(base)
                    tty["gui"]["Active"] = False
                    tty["tty"]["Active"] = True
                    change(tty)
                    chord(
                        ecodes.KEY_LEFTCTRL if expect_old_bug else ecodes.KEY_LEFTMETA
                    )
                    if expect_old_bug:
                        print(
                            "RED: unpatched daemon remaps the same-user TTY using stale GUI context",
                            flush=True,
                        )
                        change(copy.deepcopy(base))
                        chord(ecodes.KEY_LEFTCTRL)
                        replace_bridge("saturated")
                        chord(None)
                        print(
                            "RED: unpatched daemon blocks on a full bridge listen queue",
                            flush=True,
                        )
                    else:
                        for reason in (
                            "inactive",
                            "locked",
                            "greeter",
                            "unknown",
                            "remote",
                            "other-user",
                            "delayed-tty",
                        ):
                            current = copy.deepcopy(base)
                            current["signals"] = False
                            if reason == "inactive":
                                current["gui"]["Active"] = False
                            elif reason == "locked":
                                current["gui"]["LockedHint"] = True
                            elif reason == "greeter":
                                current["gui"]["Class"] = "greeter"
                            elif reason == "unknown":
                                del current["gui"]["Type"]
                            elif reason == "remote":
                                current["gui"]["Remote"] = True
                            elif reason == "other-user":
                                current["uid"] = 1001
                            elif reason == "delayed-tty":
                                current["gui"]["Active"] = False
                                current["tty"]["Active"] = True
                            # First return to the GUI so the discovery cache is eligible.
                            change(copy.deepcopy(base))
                            chord(ecodes.KEY_LEFTCTRL)
                            change(current)
                            chord(ecodes.KEY_LEFTMETA)
                            print("PASS: unchanged input for " + reason, flush=True)
                        for transition in ("tty", "locked", "owner"):
                            change(copy.deepcopy(base))
                            chord(ecodes.KEY_LEFTCTRL)
                            inflight = copy.deepcopy(base)
                            inflight["switchDuringReply"] = transition
                            change(inflight)
                            chord(ecodes.KEY_LEFTMETA)
                            print(
                                "PASS: rejected reply after in-flight " + transition,
                                flush=True,
                            )
                        change(copy.deepcopy(base))
                        chord(ecodes.KEY_LEFTCTRL)
                        stalled = copy.deepcopy(base)
                        stalled["stall"] = True
                        change(stalled)
                        started = time.monotonic()
                        chord(ecodes.KEY_LEFTMETA)
                        assert time.monotonic() - started < 1.5
                        print(
                            "PASS: unresponsive logind has a bounded pass-through timeout",
                            flush=True,
                        )
                        change(copy.deepcopy(base))
                        chord(ecodes.KEY_LEFTCTRL)
                        bridge_process.terminate()
                        bridge_process.wait(timeout=5)
                        SOCKET.unlink(missing_ok=True)
                        chord(ecodes.KEY_LEFTMETA)
                        print(
                            "PASS: bridge loss immediately restores unchanged input",
                            flush=True,
                        )
                        bridge_process = start_bridge()
                        wait_until(SOCKET.exists)
                        chord(ecodes.KEY_LEFTCTRL)
                        replace_bridge("saturated")
                        chord(ecodes.KEY_LEFTMETA)
                        print(
                            "PASS: saturated bridge cannot block physical keyboard events",
                            flush=True,
                        )
                        replace_bridge()
                        chord(ecodes.KEY_LEFTCTRL)
                        partial = copy.deepcopy(base)
                        partial["partialReply"] = True
                        change(partial)
                        chord(ecodes.KEY_LEFTMETA)
                        print(
                            "PASS: partial bridge replies cannot extend the overall deadline",
                            flush=True,
                        )
                        change(copy.deepcopy(base))
                        chord(ecodes.KEY_LEFTCTRL)
                        service.terminate()
                        service.wait(timeout=5)
                        chord(ecodes.KEY_LEFTMETA)
                        print(
                            "PASS: missing logind restores unchanged input", flush=True
                        )
                    subprocess.run(
                        ["systemctl", "stop", unit], check=not expect_old_bug
                    )
                    if expect_old_bug:
                        failed = subprocess.run(
                            ["systemctl", "is-failed", unit],
                            check=False,
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                        )
                        if failed.returncode == 0:
                            subprocess.run(
                                ["systemctl", "reset-failed", unit], check=True
                            )
                        replace_bridge()
                wait_until(lambda: output() is None)
    finally:
        for unit in ("xremap-guard-stock", "xremap-guard-fixed"):
            subprocess.run(["systemctl", "stop", unit], check=True)
            journal = subprocess.run(
                ["journalctl", "-u", unit, "--no-pager"],
                capture_output=True,
                text=True,
                check=True,
            )
            print(unit + ":\n" + journal.stdout)
        for child in reversed(children):
            if child.poll() is None:
                child.terminate()
            child.wait(timeout=5)
        for log in logs:
            log.close()
        for path in sorted(ROOT.glob("process-*.log")):
            print(path.name + ":\n" + path.read_text())
        assert bus.returncode is not None and service.returncode is not None


if __name__ == "__main__":
    if sys.argv[1] == "logind":
        logind()
    elif sys.argv[1] == "bridge":
        bridge()
    elif sys.argv[1] == "saturated":
        saturated_bridge()
    elif sys.argv[1] == "test":
        test(*sys.argv[2:])
    else:
        raise ValueError(sys.argv[1])
