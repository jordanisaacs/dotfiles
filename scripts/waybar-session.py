"""Choose status widgets for the current River window manager."""

import os
import sys

manager = os.environ.get("JD_RIVER_WM", CONFIG["defaultManager"])
configuration = CONFIG["configurations"].get(manager, CONFIG["configurations"]["oxbow"])
os.execv(
    CONFIG["waybar"],
    [
        CONFIG["waybar"],
        "--config",
        configuration,
        "--style",
        CONFIG["style"],
        *sys.argv[1:],
    ],
)
