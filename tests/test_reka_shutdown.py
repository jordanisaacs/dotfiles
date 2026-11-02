"""Stop a real isolated Emacs server while it is garbage collecting.

The previous SIGTERM path reentered Lisp cleanup while the collector had
marked Lisp objects, aborting in server-stop/expand-file-name.  The actual
managed ExecStop command must wait for a safe boundary and exit normally.
"""

import os
import resource
import shlex
import subprocess
import tempfile
import time
from pathlib import Path

resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
for attempt in range(3):
    with tempfile.TemporaryDirectory(prefix="reka-gc-shutdown-") as temporary:
        root = Path(temporary)
        fixture = root / "fixture.el"
        fixture.write_text(""";;; -*- lexical-binding: t -*-
(require 'server)
(setq server-name "reka"
      server-socket-dir (expand-file-name "emacs" (getenv "XDG_RUNTIME_DIR")))
(server-start)
(defvar reka-test-heap (make-list 2000000 0))
(write-region "ready" nil (getenv "REKA_TEST_READY") nil 'silent)
(let ((deadline (+ (float-time) 2)))
  (while (< (float-time) deadline) (garbage-collect)))
;; Process the queued emacsclient request after leaving GC safely.
(while t (accept-process-output nil 0.01))
""")
        environment = os.environ | {
            "HOME": temporary,
            "XDG_CONFIG_HOME": str(root / "config"),
            "XDG_CACHE_HOME": str(root / "cache"),
            "XDG_RUNTIME_DIR": temporary,
            "REKA_TEST_READY": str(root / "ready"),
        }
        with (root / "output.log").open("w+") as log:
            process = subprocess.Popen(
                [os.environ["EMACS"], "--batch", "-Q", "--load", str(fixture)],
                env=environment,
                stdout=log,
                stderr=subprocess.STDOUT,
            )
            try:
                deadline = time.monotonic() + 20
                while not (root / "ready").exists():
                    assert process.poll() is None, "Emacs exited before GC fixture"
                    assert time.monotonic() < deadline, "Emacs GC fixture timed out"
                    time.sleep(0.005)
                # The marker is immediately before repeated full collections.
                time.sleep(0.02)
                environment["MAINPID"] = str(process.pid)
                command = shlex.split(os.environ["STOP_COMMAND"])
                if command:
                    # Use the production command unchanged, including the socket
                    # name and explicit no-daemon fallback.
                    subprocess.run(command, env=environment, check=True, timeout=15)
                else:
                    # Negative control models systemd's former default stop path.
                    process.terminate()
                result = process.wait(timeout=15)
                log.seek(0)
                assert result == 0, (attempt, result, log.read()[-3000:])
                assert not (root / "emacs/reka").exists(), (
                    "Emacs left its server socket"
                )
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=5)
print("Production Reka ExecStop exits cleanly during GC and removes its socket")
