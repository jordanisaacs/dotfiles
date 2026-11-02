"""Update the optional IP-based timezone when the configured Wi-Fi link routes."""

import os
import re
import subprocess

if os.environ.get("IFACE") == CONFIG["interface"]:
    try:
        response = subprocess.run(
            [
                CONFIG["curl"],
                "--fail",
                "--silent",
                "--show-error",
                "--max-time",
                "15",
                "--ipv4",
                "--interface",
                CONFIG["interface"],
                "https://ipapi.co/timezone",
            ],
            text=True,
            capture_output=True,
            check=True,
            timeout=20,
        )
        timezone = response.stdout.strip()
        if not re.fullmatch(r"[A-Za-z0-9_+-]+(?:/[A-Za-z0-9_+-]+)*", timezone):
            raise ValueError
        subprocess.run(
            [CONFIG["timedatectl"], "--", "set-timezone", timezone],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=15,
        )
    except OSError, ValueError, subprocess.SubprocessError:
        print("IP timezone update unavailable; keeping the current timezone.")
