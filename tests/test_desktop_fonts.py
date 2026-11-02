"""Check shared GUI typography and independent terminal/launcher sizing."""

import configparser
import math
import os
import re
import subprocess
from pathlib import Path

config = Path(os.environ["XDG_CONFIG_HOME"])
points = float(os.environ["FONT_POINTS"])
assert math.isclose(float(os.environ["GTK_TEXT_SCALE"]), 1.0), (
    "GTK adds another text multiplier on top of the shared font size"
)

# Let Ghostty parse the real generated configuration, including its theme.
terminal = subprocess.run(
    [os.environ["GHOSTTY"], "+show-config", "--changes-only=false", "--no-pager"],
    check=True,
    capture_output=True,
    text=True,
).stdout
font = re.search(r"^font-size = ([\d.]+)$", terminal, re.MULTILINE)
assert font is not None, "Ghostty did not report an effective font size"
assert math.isclose(float(font[1]), float(os.environ["TERMINAL_FONT_POINTS"])), font[0]

gtk = configparser.ConfigParser()
gtk.read(config / "gtk-3.0/settings.ini")
gtk_points = float(gtk["Settings"]["gtk-font-name"].rsplit(" ", 1)[1])
assert math.isclose(gtk_points, points), gtk_points

subprocess.run([os.environ["FUZZEL"], "--check-config"], check=True)
menu = configparser.ConfigParser()
menu.read(config / "fuzzel/fuzzel.ini")
menu_points = re.search(r"(?:^|:)size=([\d.]+)(?:$|:)", menu["main"]["font"])
assert menu_points is not None, menu["main"]["font"]
assert menu["main"]["font"] == os.environ["LAUNCHER_FONT"]
assert menu["main"]["dpi-aware"] == "yes", (
    "Launcher sizing must not switch with output scale"
)

# CSS uses logical pixels, whereas GTK, Qt, Fuzzel and Ghostty use points.
bar = (config / "waybar/style.css").read_text()
bar_pixels = re.search(r"font-size:\s*([\d.]+)px", bar)
assert bar_pixels is not None, bar
assert math.isclose(float(bar_pixels[1]), points * 96 / 72), bar_pixels[0]
print(
    f"GUI fonts use {points:g}pt; terminal and physical-DPI launcher sizes stay independent"
)
