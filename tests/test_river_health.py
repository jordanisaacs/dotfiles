"""Native headless River integration: real XDG pongs versus a stopped loop.

Runs in Nix's build sandbox with an isolated runtime directory. Never connects
to the user's desktop or sends signals to any process outside this fixture.
"""

import json
import os
import queue
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
from contextlib import contextmanager
from pathlib import Path


@contextmanager
def compositor(executable, *, xwayland=False):
    with tempfile.TemporaryDirectory(prefix="river-health-") as directory:
        runtime = Path(directory)
        runtime.chmod(0o700)
        env = os.environ | {
            "XDG_RUNTIME_DIR": directory,
            "XDG_CONFIG_HOME": directory,
            "WLR_BACKENDS": "headless",
            "WLR_RENDERER": "pixman",
            "WLR_HEADLESS_OUTPUTS": "1",
            "HOME": directory,
        }
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("DISPLAY", None)
        arguments = [executable, "-c", os.environ["OXBOW"]]
        if xwayland:
            # Select this sandbox's Xwayland with software rendering explicitly.
            wrapper = runtime / "xwayland.py"
            wrapper.write_text(
                f"#!{sys.executable}\nimport os, sys\n"
                'os.execv(os.environ["XWAYLAND"], '
                '[os.environ["XWAYLAND"], "-glamor", "off", *sys.argv[1:]])\n'
            )
            wrapper.chmod(0o700)
            env["WLR_XWAYLAND"] = str(wrapper)
        else:
            arguments.append("-no-xwayland")
        with (runtime / "river.log").open("w+") as log:
            process = subprocess.Popen(
                arguments,
                env=env,
                stdout=log,
                stderr=log,
                start_new_session=True,
            )
            try:
                deadline = time.monotonic() + 10
                while not any(p.is_socket() for p in runtime.glob("wayland-*")):
                    if process.poll() is not None or time.monotonic() > deadline:
                        log.seek(0)
                        raise AssertionError(log.read())
                    time.sleep(0.05)
                sockets = [p for p in runtime.glob("wayland-*") if p.is_socket()]
                assert len(sockets) == 1
                env["WAYLAND_DISPLAY"] = sockets[0].name
                yield env, process
            finally:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
                log.seek(0)
                print(log.read(), flush=True)


class Observer:
    def __init__(self, env):
        self.process = subprocess.Popen(
            [os.environ["HEALTH_CLIENT"], "--watch"],
            env=env,
            stdout=subprocess.PIPE,
            text=True,
        )
        self.events = queue.Queue()
        self.latest = {}
        self.history = []
        self.thread = threading.Thread(target=self.read, daemon=True)
        self.thread.start()

    def read(self):
        for line in self.process.stdout:
            event = json.loads(line)
            self.events.put(event)

    def wait(self, predicate, timeout=15):
        deadline = time.monotonic() + timeout
        while not predicate(self.latest):
            assert self.process.poll() is None, "Observer unexpectedly exited"
            if time.monotonic() > deadline:
                raise AssertionError(
                    f"Timed out: latest={self.latest}, history={self.history}"
                ) from None
            try:
                event = self.events.get(timeout=max(0.01, deadline - time.monotonic()))
            except queue.Empty:
                raise AssertionError(
                    f"Timed out: latest={self.latest}, history={self.history}"
                ) from None
            self.latest[event["identifier"]] = event
            self.history.append(event)
        return self.latest

    def stop(self):
        self.process.terminate()
        self.process.wait(timeout=5)


def states(values, app_id, status):
    return [
        event
        for event in values.values()
        if event["app_id"] == app_id and event["status"] == status
    ]


# Test-only capabilities must never be available in the installed observer.
for arguments in [[], ["--fixture", "never-created"], ["--sandbox-check"]]:
    rejected = subprocess.run(
        [os.environ["HEALTH_CLIENT"], *arguments],
        text=True,
        capture_output=True,
        check=False,
    )
    assert rejected.returncode == 2, rejected
    assert "Usage: river-health --watch" in rejected.stderr

with compositor(os.environ["STOCK_RIVER"]) as (env, river):
    absent = subprocess.run(
        [os.environ["HEALTH_CLIENT"], "--watch"],
        env=env,
        text=True,
        capture_output=True,
        timeout=5,
        check=False,
    )
    assert absent.returncode == 3, absent
    assert "Waiting for app" in absent.stderr
    assert river.poll() is None
print("RED: stock River has no native health API; observer fails honestly", flush=True)

with compositor(os.environ["HEALTH_RIVER"]) as (env, river):
    security = subprocess.run(
        [os.environ["HEALTH_FIXTURE"], "--sandbox-check"],
        env=env,
        text=True,
        capture_output=True,
        check=True,
        timeout=5,
    )
    assert security.stdout.strip() == "sandbox-context-filtered"
    children = []
    observers = []
    vetoes = queue.Queue()
    pings = queue.Queue()
    try:
        for name in ["veto", "blocked"]:
            children.append(
                subprocess.Popen(
                    [os.environ["HEALTH_FIXTURE"], "--fixture", name],
                    env=env,
                    stdout=subprocess.PIPE,
                    text=True,
                )
            )

        def collect_vetoes():
            for line in children[0].stdout:
                if line.strip() == "ping":
                    pings.put("ping")
                else:
                    vetoes.put(line.strip())

        threading.Thread(target=collect_vetoes, daemon=True).start()
        monitor = Observer(env)
        observers.append(monitor)
        monitor.wait(
            lambda v: (
                len(states(v, "veto", "responsive")) == 2
                and len(states(v, "blocked", "responsive")) == 2
            )
        )
        identifiers = [
            e["identifier"] for e in states(monitor.latest, "veto", "responsive")
        ]
        for identifier in identifiers:
            subprocess.run(
                [
                    os.environ["OXCTL"],
                    "window",
                    "close",
                    f"--identifier=^{re.escape(identifier)}$",
                ],
                env=env,
                check=True,
                capture_output=True,
                text=True,
                timeout=5,
            )
        # A real close request reached each window; the app vetoes it and keeps
        # dispatching pings. A pending window alone must never imply a hang.
        assert vetoes.get(timeout=5) == "close-vetoed"
        assert vetoes.get(timeout=5) == "close-vetoed"
        children[1].send_signal(signal.SIGSTOP)
        monitor.wait(
            lambda v: len(states(v, "blocked", "unresponsive")) == 2, timeout=15
        )
        assert len(states(monitor.latest, "veto", "responsive")) == 2
        assert all(p.poll() is None for p in children)
        children[1].send_signal(signal.SIGCONT)
        monitor.wait(lambda v: len(states(v, "blocked", "responsive")) == 2)
        assert not any(
            e["status"] == "unresponsive" and e["app_id"] == "veto"
            for e in monitor.history
        )
        children[1].send_signal(signal.SIGUSR1)
        monitor.wait(lambda v: len(states(v, "blocked", "closed")) == 1)
        # Representative surface changes while the same native client survives.
        assert len(states(monitor.latest, "blocked", "responsive")) == 1
        children[1].send_signal(signal.SIGSTOP)
        monitor.wait(
            lambda v: any(
                e["app_id"] == "blocked" and e["native_state"] == 2 for e in v.values()
            ),
            timeout=15,
        )
        children[1].kill()
        children[1].wait(timeout=5)
        monitor.wait(lambda v: len(states(v, "blocked", "closed")) == 2)
        # A different client dies while its native ping is outstanding, before
        # the ten-second timeout. Both observers must become inert safely.
        dying = subprocess.Popen(
            [os.environ["HEALTH_FIXTURE"], "--fixture", "dying"],
            env=env,
            stdout=subprocess.PIPE,
            text=True,
        )
        children.append(dying)
        monitor.wait(lambda v: len(states(v, "dying", "responsive")) == 2)
        dying.send_signal(signal.SIGSTOP)
        time.sleep(1.3)
        dying.kill()
        dying.wait(timeout=5)
        monitor.wait(lambda v: len(states(v, "dying", "closed")) == 2)
        monitor.stop()
        assert children[0].poll() is None
        assert river.poll() is None
        # Dropping all observers tears down probe timers. A fresh connection
        # starts cleanly and obtains native results for the surviving windows.
        again = Observer(env)
        observers.append(again)
        again.wait(lambda v: len(states(v, "veto", "responsive")) == 2)
        again.stop()
        # Allow one already-sent native ping to finish, then ensure monitoring
        # has no periodic side effects once the last observer disconnects.
        time.sleep(0.3)
        while not pings.empty():
            pings.get_nowait()
        time.sleep(1.4)
        assert pings.empty(), "Native pings continued without observers"
        assert river.poll() is None
        print(
            "GREEN: close veto responsive; blocked loop times out and recovers; shared-client, close, destruction and reconnect safe",
            flush=True,
        )
    finally:
        for monitor in observers:
            if monitor.process.poll() is None:
                monitor.stop()
        for child in children:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=5)

with compositor(os.environ["HEALTH_RIVER"], xwayland=True) as (env, river):
    # No PID/server responsiveness proxy: the real X11 window must remain
    # explicitly unsupported, even though Xwayland itself dispatches events.
    sockets = sorted(Path("/tmp/.X11-unix").glob("X[0-9]*"))
    assert len(sockets) == 1, sockets
    env["DISPLAY"] = ":" + sockets[0].name[1:]
    x11 = subprocess.Popen(
        [os.environ["XMESSAGE"], "-name", "health-xwayland", "Unsupported fixture"],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    monitor = Observer(env)
    try:
        monitor.wait(
            lambda values: any(event["native_state"] == 3 for event in values.values())
        )
        assert len(monitor.latest) == 1, monitor.latest
        assert all(event["status"] == "unknown" for event in monitor.latest.values())
        assert x11.poll() is None, x11.stderr.read()
        print("GREEN: real Xwayland window reports unsupported, never a fake diagnosis")
    finally:
        monitor.stop()
        if x11.poll() is None:
            x11.terminate()
            x11.wait(timeout=5)
