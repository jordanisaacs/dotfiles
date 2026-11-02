"""Keep the selected Kvantum theme while disabling transparent windows."""

import configparser
import shutil
import sys
from pathlib import Path

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
shutil.copytree(source, destination)
for path in destination.glob("*.kvconfig"):
    # QSettings permits repeated groups; the upstream Arc theme uses them.
    settings = configparser.ConfigParser(interpolation=None, strict=False)
    settings.optionxform = str
    settings.read(path)
    general = settings["%General"]
    for option in ("translucent_windows", "blurring", "popup_blurring"):
        general[option] = "false"
    for option in ("reduce_window_opacity", "reduce_menu_opacity"):
        general[option] = "0"
    path.chmod(0o644)
    with path.open("w") as stream:
        settings.write(stream)
