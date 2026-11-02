"""Record only synthetic input sent to a private Ghostty test instance."""

import os
import tty
from pathlib import Path

tty.setraw(0)
destination = Path("/tmp/reka-ghostty-input")
destination.touch(mode=0o600)
while True:
    data = os.read(0, 4096)
    if not data:
        break
    with destination.open("ab") as stream:
        stream.write(data)
