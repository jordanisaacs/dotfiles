"""Request normal Emacs shutdown and wait before systemd sends stop signals."""

import os
import select
import subprocess
import time

# ExecStop receives MAINPID from systemd. Open a stable process reference before
# contacting Emacs, avoiding PID reuse or racing its very last cleanup steps.
main_pid = os.environ.get("MAINPID")
if not main_pid:
    # systemd also invokes ExecStop when the main process already exited.
    raise SystemExit(0)
try:
    descriptor = os.pidfd_open(int(main_pid))
except ProcessLookupError:
    raise SystemExit(0) from None
try:
    deadline = time.monotonic() + 8
    subprocess.run(
        [
            CONFIG["emacsclient"],
            "--socket-name",
            "reka",
            "--alternate-editor=" + CONFIG["alternateEditor"],
            "--eval",
            "(kill-emacs 0)",
        ],
        check=True,
        timeout=8,
    )
    # The server kill-hook closes the client before Emacs finishes exiting.
    # Returning then lets systemd SIGTERM the still-running shutdown path.
    poll = select.poll()
    poll.register(descriptor, select.POLLIN)
    remaining = max(0, int((deadline - time.monotonic()) * 1000))
    if not poll.poll(remaining):
        raise TimeoutError("Emacs did not finish its requested shutdown")
finally:
    os.close(descriptor)
