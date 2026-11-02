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
terminal_family = re.search(r"^font-family = (.*)$", terminal, re.MULTILINE)
assert terminal_family is not None
assert terminal_family[1] == os.environ["MONOSPACE_FONT"], terminal_family[1]
preferred_terminal = float(os.environ["TERMINAL_PREFERRED_FONT_POINTS"])
output_scale = float(os.environ["OUTPUT_SCALE"])
physical_terminal_pixels = float(font[1]) * 96 / 72 * output_scale
preferred_terminal_pixels = preferred_terminal * 96 / 72
# Native font/config floats have finite precision; differences below a text
# rasterizer's 1/64-pixel unit must not reject equivalent physical sizing.
assert math.isclose(
    physical_terminal_pixels, preferred_terminal_pixels, abs_tol=1 / 64
), (
    physical_terminal_pixels,
    preferred_terminal_pixels,
)

gtk = configparser.ConfigParser()
gtk.read(config / "gtk-3.0/settings.ini")
gtk_points = float(gtk["Settings"]["gtk-font-name"].rsplit(" ", 1)[1])
assert math.isclose(gtk_points, points), gtk_points
assert gtk["Settings"]["gtk-font-name"].rsplit(" ", 1)[0] == os.environ["NORMAL_FONT"]
assert os.environ["NORMAL_FONT"] != os.environ["MONOSPACE_FONT"]

subprocess.run([os.environ["FUZZEL"], "--check-config"], check=True)
menu = configparser.ConfigParser()
menu.read(config / "fuzzel/fuzzel.ini")
menu_points = re.search(r"(?:^|:)size=([\d.]+)(?:$|:)", menu["main"]["font"])
assert menu_points is not None, menu["main"]["font"]
assert menu["main"]["font"] == os.environ["LAUNCHER_FONT"]
assert menu["main"]["font"].startswith(os.environ["MONOSPACE_FONT"] + ":")
assert menu["main"]["dpi-aware"] == "yes", (
    "Launcher sizing must not switch with output scale"
)

# CSS uses logical pixels, whereas GTK, Qt, Fuzzel and Ghostty use points.
bar = (config / "waybar/style.css").read_text()
bar_pixels = re.search(r"font-size:\s*([\d.]+)px", bar)
assert bar_pixels is not None, bar
assert math.isclose(
    float(bar_pixels[1]), points * 96 / 72 * float(os.environ["BAR_SCALE"])
), bar_pixels[0]
print(
    f"GUI fonts use {points:g}pt; terminal and physical-DPI launcher sizes stay independent"
)
