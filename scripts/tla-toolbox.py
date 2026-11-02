"""Run the bundled legacy SWT on its working Xwayland backend."""

import os
import sys
from pathlib import Path

os.environ["GDK_BACKEND"] = "x11"
directory = Path(__file__).resolve().parent.parent / "libexec/toolbox"
arguments = ["-install", str(directory), *sys.argv[1:]]
if "-data" not in arguments:
    arguments = ["-data", str(Path.home() / ".tla-toolbox"), *arguments]
os.chdir(directory)
executable = str(directory / "toolbox")
os.execv(executable, [executable, *arguments])
