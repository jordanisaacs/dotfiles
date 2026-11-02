"""Pass Waybar's actual output to the upstream Oxbow widget stream."""

import os
import sys

# Keep widget dependencies private to the widget. The bar and its launchers
# inherit the full session PATH, including systemd-run and desktop applications.
os.environ["PATH"] = CONFIG["path"] + os.pathsep + os.environ.get("PATH", "")
arguments = [CONFIG["shell"], CONFIG["script"], *sys.argv[1:]]
if output := os.environ.get("WAYBAR_OUTPUT_NAME"):
    arguments.append(output)
os.execv(arguments[0], arguments)
