"""Exercise real tray scroll and CLI gain limits on a private silent audio graph."""

import argparse
import configparser
import json
import os
import resource
import select
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import dbus

NORMAL = 65536
WATCHER = """
import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib
DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
name = dbus.service.BusName("org.kde.StatusNotifierWatcher", bus=bus)
class Watcher(dbus.service.Object):
    def __init__(self):
        super().__init__(bus, "/StatusNotifierWatcher")
        self.items = []
    @dbus.service.method("org.kde.StatusNotifierWatcher", in_signature="s", sender_keyword="sender")
    def RegisterStatusNotifierItem(self, service, sender=None):
        entry = sender + service if service.startswith("/") else service + "/StatusNotifierItem"
        self.items.append(entry)
        self.StatusNotifierItemRegistered(entry)
    @dbus.service.method("org.kde.StatusNotifierWatcher", in_signature="s")
    def RegisterStatusNotifierHost(self, service):
        pass
    @dbus.service.signal("org.kde.StatusNotifierWatcher", signature="s")
    def StatusNotifierItemRegistered(self, item):
        pass
    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
    def Get(self, interface, property):
        return self.GetAll(interface)[property]
    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return {
            "RegisteredStatusNotifierItems": dbus.Array(self.items, signature="s"),
            "IsStatusNotifierHostRegistered": dbus.Boolean(True),
            "ProtocolVersion": dbus.Int32(0),
        }
watcher = Watcher()
GLib.MainLoop().run()
"""


def wait_for(function, description, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if result := function():
                return result
        except dbus.DBusException, subprocess.CalledProcessError:
            pass
        time.sleep(0.05)
    raise AssertionError(f"Timed out waiting for {description}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--stock", action="store_true")
    arguments = parser.parse_args()
    arguments.output.mkdir(parents=True)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    with tempfile.TemporaryDirectory(prefix="audio-volume-") as directory:
        root = Path(directory)
        runtime = root / "runtime"
        runtime.mkdir(mode=0o700)
        environment = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("PIPEWIRE_", "PULSE_", "DBUS_"))
            and key
            not in {"DISPLAY", "WAYLAND_DISPLAY", "SESSION_MANAGER", "XAUTHORITY"}
        }
        environment.update(
            XDG_RUNTIME_DIR=str(runtime),
            XDG_CONFIG_HOME=str(root / "config"),
            XDG_CACHE_HOME=str(root / "cache"),
            XDG_STATE_HOME=str(root / "state"),
            HOME=str(root),
            GDK_BACKEND="x11",
            PULSE_SERVER=f"unix:{runtime}/pulse/native",
        )
        processes = []
        logs = []

        def start(name, command, **options):
            log = (arguments.output / f"{name}.log").open("w")
            logs.append(log)
            child = subprocess.Popen(
                command,
                env=environment,
                stdout=log,
                stderr=subprocess.STDOUT,
                **options,
            )
            processes.append(child)
            return child

        def run(command, check=True):
            return subprocess.run(
                command, env=environment, check=check, capture_output=True, text=True
            )

        def pactl(*command):
            return run(["pactl", *command]).stdout.strip()

        def volumes(kind="sinks"):
            entries = json.loads(pactl("--format=json", "list", kind))
            return [channel["value"] for channel in entries[0]["volume"].values()]

        def wait_volume(value):
            wait_for(lambda: max(volumes()) == value, f"sink volume {value}")

        def set_sink(percent):
            pactl("set-sink-volume", "volume-fixture", percent)
            time.sleep(0.15)

        try:
            read_fd, write_fd = os.pipe()
            start(
                "xserver",
                [
                    "Xvfb",
                    "-displayfd",
                    str(write_fd),
                    "-screen",
                    "0",
                    "640x480x24",
                    "-nolisten",
                    "tcp",
                ],
                pass_fds=(write_fd,),
            )
            os.close(write_fd)
            with os.fdopen(read_fd) as display:
                assert select.select([display], [], [], 10)[0]
                environment["DISPLAY"] = ":" + display.readline().strip()
            address = root / "bus"
            start(
                "dbus",
                [
                    "dbus-daemon",
                    "--config-file=" + os.environ["DBUS_SESSION_CONFIG"],
                    "--nofork",
                    f"--address=unix:path={address}",
                ],
            )
            environment["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={address}"
            wait_for(lambda: address.exists(), "private D-Bus")
            connection = dbus.bus.BusConnection(environment["DBUS_SESSION_BUS_ADDRESS"])
            start("watcher", [sys.executable, "-c", WATCHER])
            wait_for(
                lambda: connection.name_has_owner("org.kde.StatusNotifierWatcher"),
                "tray watcher",
            )
            start("pipewire", ["pipewire"])
            wait_for(lambda: (runtime / "pipewire-0").exists(), "private PipeWire")
            wireplumber = root / "config/wireplumber/wireplumber.conf.d"
            wireplumber.mkdir(parents=True)
            (wireplumber / "99-volume-fixture.conf").write_text("""
                wireplumber.profiles = {
                    main = {
                        monitor.alsa = disabled
                        monitor.bluez = disabled
                        monitor.bluez-midi = disabled
                        monitor.v4l2 = disabled
                        monitor.libcamera = disabled
                    }
                }
            """)
            start("wireplumber", ["wireplumber"])
            start("pulse", ["pipewire-pulse"])
            wait_for(lambda: pactl("info"), "private PulseAudio compatibility server")
            pactl("load-module", "module-null-sink", "sink_name=volume-fixture")
            wait_for(
                lambda: pactl("set-default-sink", "volume-fixture") or True,
                "the private null sink",
            )
            pactl("set-default-source", "volume-fixture.monitor")
            sinks = json.loads(pactl("--format=json", "list", "sinks"))
            assert [sink["name"] for sink in sinks] == ["volume-fixture"], sinks
            assert json.loads(pactl("--format=json", "list", "sink-inputs")) == []
            pactl("set-source-volume", "volume-fixture.monitor", "31%")
            source_before = volumes("sources")
            pactl("set-sink-mute", "volume-fixture", "1")
            unit = configparser.ConfigParser(interpolation=None, strict=False)
            unit.read(os.environ["PASYSTRAY_UNIT"])
            command = shlex.split(unit["Service"]["ExecStart"])
            if arguments.stock:
                command = [
                    arg for arg in command if not arg.startswith("--volume-max=")
                ]
            start("pasystray", [*command, "--notify=none"])
            properties = dbus.Interface(
                connection.get_object(
                    "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher"
                ),
                "org.freedesktop.DBus.Properties",
            )
            item = wait_for(
                lambda: properties.Get(
                    "org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems"
                ),
                "pasystray's native tray item",
            )[0]
            service, path = str(item).split("/", 1)
            tray = dbus.Interface(
                connection.get_object(service, "/" + path), "org.kde.StatusNotifierItem"
            )
            # Give native PulseAudio subscriptions time to discover the dummy output.
            time.sleep(0.3)
            set_sink("149%")
            tray.Scroll(dbus.Int32(-120), "vertical")
            time.sleep(0.2)
            observed = max(volumes())
            assert observed <= NORMAL, (
                f"Tray scrolling exceeded unity gain: {observed * 100 / NORMAL:.2f}%"
            )
            for start_percent in ("97%", "99%", "100%"):
                set_sink(start_percent)
                for _ in range(4):
                    tray.Scroll(dbus.Int32(-120), "vertical")
                    time.sleep(0.1)
                wait_volume(NORMAL)
            set_sink("1%")
            tray.Scroll(dbus.Int32(120), "vertical")
            wait_volume(0)
            assert volumes("sources") == source_before
            assert "yes" in pactl("get-sink-mute", "volume-fixture")

            tools = os.environ["SOUND_TOOLS"]
            set_sink("99%")
            run([tools, "vol", "up", "5"])
            wait_volume(NORMAL)
            run([tools, "vol", "up", "5"])
            wait_volume(NORMAL)
            assert run([tools, "vol", "get"]).stdout.strip() == "100%"
            run([tools, "vol", "down", "150"])
            wait_volume(0)
            run([tools, "vol", "set", "80"])
            assert max(volumes()) == 80 * NORMAL // 100
            pactl("set-sink-volume", "volume-fixture", "80%", "40%")
            run([tools, "vol", "up", "50"])
            channels = volumes()
            assert (
                max(channels) == NORMAL and abs(channels[1] * 2 - channels[0]) <= 2
            ), channels
            assert "yes" in pactl("get-sink-mute", "volume-fixture")
            assert volumes("sources") == source_before
            # Explicit CLI overrides remain available; accidental UI scrolling
            # and hardware keys never pass this amplification override.
            run([tools, "vol", "up", "50", "150"])
            assert max(volumes()) == NORMAL * 150 // 100
            run([tools, "vol", "up"])
            wait_volume(NORMAL)
            invalid = run([tools, "vol", "up", "-1"], check=False)
            assert invalid.returncode != 0
            wait_volume(NORMAL)
            source_mute = pactl("get-source-mute", "volume-fixture.monitor")
            run([tools, "mic", "toggle"])
            assert pactl("get-source-mute", "volume-fixture.monitor") != source_mute
            assert "yes" in pactl("get-sink-mute", "volume-fixture")
            wait_volume(NORMAL)
            run([tools, "mic", "toggle"])
            assert pactl("get-source-mute", "volume-fixture.monitor") == source_mute
            assert volumes("sources") == source_before

            config = root / "autostart-config"
            autostart = config / "autostart"
            autostart.mkdir(parents=True)
            desktop = autostart / "pasystray.desktop"
            environment.update(
                XDG_CONFIG_HOME=str(config),
                XDG_CONFIG_DIRS=str(root / "no-system-config"),
            )
            generator = os.environ["XDG_GENERATOR"]
            generated = root / "generated"
            generated.mkdir()
            shutil.copyfile(os.environ["PASYSTRAY_STOCK_ENTRY"], desktop)
            run([generator, str(generated), str(generated), str(generated)])
            assert (generated / "app-pasystray@autostart.service").exists()
            shutil.copyfile(os.environ["PASYSTRAY_USER_ENTRY"], desktop)
            hidden = root / "generated-hidden"
            hidden.mkdir()
            run([generator, str(hidden), str(hidden), str(hidden)])
            assert not (hidden / "app-pasystray@autostart.service").exists()
            (arguments.output / "result.json").write_text(
                json.dumps(
                    {
                        "tray_scroll_maximum": 100,
                        "ordinary_cli_maximum": 100,
                        "intentional_cli_override": 150,
                        "source_volume_unchanged": True,
                        "mute_preserved": True,
                        "physical_devices": False,
                    },
                    indent=2,
                )
                + "\n"
            )
        except Exception:
            for log in logs:
                log.flush()
                print(Path(log.name).name, Path(log.name).read_text()[-5000:])
            raise
        finally:
            for child in reversed(processes):
                if child.poll() is None:
                    child.terminate()
                    try:
                        child.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait()
            for log in logs:
                log.close()


if __name__ == "__main__":
    main()
