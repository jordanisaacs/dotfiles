"""Check generated desktop settings and the assets they select."""

import configparser
import json
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

config = Path(os.environ["XDG_CONFIG_HOME"])
kde = configparser.ConfigParser(strict=False)
kde.read(config / "kdeglobals")
icon = kde["Icons"]["Theme"]
assert (Path(os.environ["ICON_ROOT"]) / icon / "index.theme").is_file(), icon

selector = (config / "Kvantum/kvantum.kvconfig").read_text().strip()
theme = selector.removeprefix("theme=")
assert selector.startswith("theme="), selector
for extension in ("svg", "kvconfig"):
    asset = config / "Kvantum" / theme / f"{theme}.{extension}"
    assert asset.is_file(), f"Selected Kvantum theme has no {asset}"

# Exercise KDE's actual palette loader, which Dolphin uses independently of
# the Qt widget style, instead of only checking that color keys were generated.
with tempfile.TemporaryDirectory() as temporary:
    runtime = Path(temporary) / "runtime"
    runtime.mkdir(mode=0o700)
    environment = os.environ | {
        "HOME": temporary,
        "XDG_CACHE_HOME": temporary,
        "XDG_RUNTIME_DIR": str(runtime),
        "WAYLAND_DISPLAY": "theme-test-wayland",
        "DESKTOP_SCREENSHOT": str(Path(temporary) / "desktop-theme.png"),
    }
    with (Path(temporary) / "weston.log").open("w+") as log:
        compositor = subprocess.Popen(
            [
                os.environ["WESTON"],
                "--backend=headless",
                "--renderer=pixman",
                "--socket=theme-test-wayland",
                "--width=1280",
                "--height=800",
                "--idle-time=0",
                "--shell=kiosk-shell.so",
            ],
            env=environment,
            stdout=log,
            stderr=subprocess.STDOUT,
        )
        try:
            for _ in range(100):
                if (runtime / "theme-test-wayland").is_socket():
                    break
                if compositor.poll() is not None:
                    raise RuntimeError("Headless Wayland compositor exited")
                time.sleep(0.05)
            else:
                raise TimeoutError("Headless Wayland compositor did not start")
            subprocess.run(
                [os.environ["KDE_PALETTE_CHECK"]],
                check=True,
                env=environment,
                timeout=20,
            )
        except Exception:
            log.seek(0)
            print(log.read())
            raise
        finally:
            compositor.terminate()
            compositor.wait(timeout=10)

preferences = {}
for key, value in re.findall(
    r'^user_pref\("([^"]+)", (.*)\);$',
    Path(os.environ["FIREFOX_USER_JS"]).read_text(),
    re.MULTILINE,
):
    preferences[key] = json.loads(value)
assert preferences["extensions.activeThemeID"] == "firefox-compact-dark@mozilla.org"
assert preferences["layout.css.prefers-color-scheme.content-override"] == 0
assert preferences["sidebar.verticalTabs"] is True
assert preferences["sidebar.visibility"] == "expand-on-hover"
assert preferences["sidebar.expandOnHover"] is True
print("Desktop dark palette, selected assets and Firefox appearance checks passed")
