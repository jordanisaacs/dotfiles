"""Synthetic keyboard control confined to the native input regression VM."""

import json
import select
import socket
import socketserver
import subprocess
import sys
import time
from contextlib import closing
from pathlib import Path

from evdev import InputDevice, UInput, ecodes, list_devices

assert Path("/etc/mac-input-vm").exists(), (
    "Refusing input access outside the regression VM"
)
ROOT = Path("/run/mac-input")
SOCKET = ROOT / "control.sock"


def sessions():
    rows = json.loads(
        subprocess.check_output(
            ["loginctl", "list-sessions", "--json=short"], text=True
        )
    )
    result = []
    for row in rows:
        if row.get("uid") != 1000:
            continue
        raw = subprocess.check_output(
            [
                "loginctl",
                "show-session",
                row["session"],
                "-p",
                "Active",
                "-p",
                "Type",
                "-p",
                "Class",
                "-p",
                "LockedHint",
                "-p",
                "VTNr",
            ],
            text=True,
        )
        properties = dict(line.split("=", 1) for line in raw.splitlines())
        if properties.get("Active") == "yes" and properties.get("Class") == "user":
            result.append(properties)
    print(json.dumps(result))


def source():
    ROOT.mkdir(mode=0o700, exist_ok=True)
    keys = list(range(ecodes.KEY_ESC, ecodes.KEY_MICMUTE + 1))
    with UInput({ecodes.EV_KEY: keys}, name="mac-profile-test-keyboard") as keyboard:

        class Handler(socketserver.StreamRequestHandler):
            def handle(self):
                request = json.loads(self.rfile.readline())
                output = None
                for path in list_devices():
                    with closing(InputDevice(path)) as device:
                        if device.name.startswith("xremap"):
                            output = path
                            break
                assert output, "No native xremap output keyboard"
                with closing(InputDevice(output)) as receiver:
                    while select.select([receiver.fd], [], [], 0)[0]:
                        list(receiver.read())
                    for key, value in request:
                        keyboard.write(
                            ecodes.EV_KEY, getattr(ecodes, "KEY_" + key), value
                        )
                        keyboard.syn()
                        time.sleep(0.025)
                    pressed = set()
                    observations = []
                    deadline = time.monotonic() + 2
                    while time.monotonic() < deadline:
                        if not select.select([receiver.fd], [], [], 0.1)[0]:
                            if observations:
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
                                observations.append(
                                    {
                                        "control": bool(
                                            {ecodes.KEY_LEFTCTRL, ecodes.KEY_RIGHTCTRL}
                                            & pressed
                                        ),
                                        "command": bool(
                                            {ecodes.KEY_LEFTMETA, ecodes.KEY_RIGHTMETA}
                                            & pressed
                                        ),
                                        "option": bool(
                                            {ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT}
                                            & pressed
                                        ),
                                    }
                                )
                    self.wfile.write((json.dumps(observations) + "\n").encode())

        with socketserver.UnixStreamServer(str(SOCKET), Handler) as server:
            (ROOT / "ready").touch()
            server.serve_forever()


def chord():
    keys = sys.argv[2:] or ["LEFTMETA", "C"]
    request = [[key, 1] for key in keys] + [[key, 0] for key in reversed(keys)]
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(5)
        connection.connect(str(SOCKET))
        connection.sendall((json.dumps(request) + "\n").encode())
        with connection.makefile("r") as reader:
            print(reader.readline().strip())


if __name__ == "__main__":
    {"source": source, "chord": chord, "sessions": sessions}[sys.argv[1]]()
