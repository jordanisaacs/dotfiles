"""Mark execution only after real greetd completes greeter PAM startup."""

import os
import signal
from pathlib import Path

Path("/tmp/greetd-greeter-started").write_text(str(os.getuid()))
while True:
    signal.pause()
