"""One short-lived authenticated administrative connection per CLI invocation."""

import contextlib
import contextvars
import json
import os
import selectors
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

PHASES = {"review", "prerequisites", "packages", "accounts", "inetd", "complete"}
MAX_OUTPUT = 16 * 1024 * 1024
_CURRENT = contextvars.ContextVar("rsync_net_ssh_invocation", default=None)


class SSHError(ValueError):
    """A failed or expired authenticated administrative session."""


def command(
    manifest,
    remote=None,
    *,
    executable="ssh",
    admin_identity=None,
    admin_agent_public_key=None,
    known_hosts=None,
):
    connection = manifest["connection"]
    arguments = [
        executable,
        "-T",
        "-F",
        "/dev/null",
        "-p",
        str(connection["port"]),
        "-o",
        "BatchMode=no" if admin_agent_public_key is not None else "BatchMode=yes",
        "-o",
        "PreferredAuthentications=publickey",
        "-o",
        "IdentitiesOnly=yes",
        "-o",
        "StrictHostKeyChecking=yes",
        "-o",
        "GlobalKnownHostsFile=/dev/null",
        "-o",
        "ForwardAgent=no",
        "-o",
        "ClearAllForwardings=yes",
        "-o",
        "ConnectTimeout=30",
    ]
    if admin_identity is not None:
        arguments += ["-i", str(admin_identity), "-o", "IdentityAgent=none"]
    elif admin_agent_public_key is not None:
        arguments += ["-i", str(admin_agent_public_key)]
    else:
        raise SSHError("remote administration requires an explicit identity selector")
    if known_hosts is not None:
        arguments += [
            "-o",
            "UserKnownHostsFile=" + json.dumps(str(known_hosts), ensure_ascii=False),
        ]
    arguments += [f"{connection['user']}@{connection['host']}"]
    if remote is not None:
        arguments += [remote]
    return arguments


class Session:
    def __init__(
        self,
        manifest,
        *,
        executable="ssh",
        fail_executable=None,
        admin_identity=None,
        admin_agent_public_key=None,
        known_hosts=None,
        connect_timeout=60,
    ):
        self.base = command(
            manifest,
            executable=executable,
            admin_identity=admin_identity,
            admin_agent_public_key=admin_agent_public_key,
            known_hosts=known_hosts,
        )
        self.fail_executable = fail_executable or shutil.which("false")
        if not self.fail_executable or not Path(self.fail_executable).is_absolute():
            raise SSHError("native SSH fallback blocker is unavailable")
        self.connect_timeout = connect_timeout
        self.agent_identity = admin_agent_public_key is not None
        self.master = None
        self.temporary = None
        self.socket = None
        self.closed = False
        self._diagnostic_thread = None

    def _start(self):
        if self.closed:
            raise SSHError("administrative SSH session ended; retry explicitly")
        if self.master is not None:
            if self.master.poll() is not None:
                raise SSHError(
                    "authenticated administrative SSH connection was lost; no reauthentication attempted"
                )
            return
        self.temporary = tempfile.TemporaryDirectory(prefix="rsn-", dir="/tmp")
        directory = Path(self.temporary.name)
        info = directory.stat()
        if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
            self.close()
            raise SSHError("SSH control directory is not private")
        self.socket = directory / "control"
        arguments = self.base[:-1] + [
            "-M",
            "-N",
            "-S",
            str(self.socket),
            "-o",
            "ControlMaster=yes",
            "-o",
            "ControlPersist=no",
            "-o",
            "ServerAliveInterval=15",
            "-o",
            "ServerAliveCountMax=2",
            self.base[-1],
        ]
        try:
            if self.agent_identity:
                print(
                    "rsync-net: waiting for administrative SSH agent; unlock or touch the selected hardware key when prompted",
                    file=sys.stderr,
                    flush=True,
                )
            self.master = subprocess.Popen(
                arguments,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
            )

            # Drain diagnostics without exposing server banners or credential data.
            def drain():
                while self.master.stderr.read(65536):
                    pass

            self._diagnostic_thread = threading.Thread(target=drain, daemon=True)
            self._diagnostic_thread.start()
            deadline = time.monotonic() + self.connect_timeout
            while True:
                if self.master.poll() is not None:
                    raise SSHError(
                        "administrative SSH authentication failed; check the pinned host and selected identity"
                    )
                try:
                    metadata = self.socket.lstat()
                except FileNotFoundError:
                    metadata = None
                if metadata is not None:
                    if (
                        not stat.S_ISSOCK(metadata.st_mode)
                        or metadata.st_uid != os.getuid()
                    ):
                        raise SSHError("invalid administrative SSH control socket")
                    return
                if time.monotonic() >= deadline:
                    raise SSHError("administrative SSH authentication timed out")
                time.sleep(0.02)
        except BaseException:
            self.close()
            raise

    def run(self, remote, *, input="", timeout=180, progress=False):
        self._start()
        arguments = self.base[:-1] + [
            "-S",
            str(self.socket),
            "-o",
            "ControlMaster=no",
            "-o",
            "ControlPersist=no",
            # OpenSSH otherwise silently opens a fresh connection after mux loss.
            "-o",
            "ProxyCommand=" + shlex.quote(self.fail_executable),
            self.base[-1],
            remote,
        ]
        process = None
        try:
            process = subprocess.Popen(
                arguments,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            output, errors = _exchange(
                process, input.encode(), timeout=timeout, progress=progress
            )
            return subprocess.CompletedProcess(
                arguments,
                process.returncode,
                output.decode(),
                errors.decode(errors="replace"),
            )
        except subprocess.TimeoutExpired:
            self.close()
            raise subprocess.TimeoutExpired(
                "administrative SSH operation", timeout
            ) from None
        except BaseException:
            self.close()
            raise
        finally:
            if process is not None:
                _stop(process)
                for pipe in (process.stdin, process.stdout, process.stderr):
                    pipe.close()

    def close(self):
        if self.closed:
            return
        self.closed = True
        if self.master is not None:
            _stop(self.master)
            if self._diagnostic_thread is not None:
                self._diagnostic_thread.join(timeout=1)
            self.master.stderr.close()
        if self.temporary is not None:
            self.temporary.cleanup()

    def __enter__(self):
        return self

    def __exit__(self, *_exc):
        self.close()


def _stop(process):
    if process.poll() is not None:
        process.wait()
        return
    process.terminate()
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        process.kill()  # Only our own local SSH child, never a server process.
        process.wait(timeout=2)


def _exchange(process, payload, *, timeout, progress):
    output, errors, pending = bytearray(), bytearray(), bytearray()
    deadline = time.monotonic() + timeout
    written = 0
    with selectors.DefaultSelector() as selector:
        for pipe in (process.stdin, process.stdout, process.stderr):
            os.set_blocking(pipe.fileno(), False)
        if payload:
            selector.register(process.stdin, selectors.EVENT_WRITE)
        else:
            process.stdin.close()
        selector.register(process.stdout, selectors.EVENT_READ)
        selector.register(process.stderr, selectors.EVENT_READ)
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(process.args, timeout)
            for key, _events in selector.select(min(0.1, remaining)):
                pipe = key.fileobj
                if pipe is process.stdin:
                    try:
                        written += os.write(
                            pipe.fileno(), payload[written : written + 65536]
                        )
                    except BrokenPipeError:
                        written = len(payload)
                    if written == len(payload):
                        selector.unregister(pipe)
                        pipe.close()
                    continue
                chunk = os.read(pipe.fileno(), 65536)
                if not chunk:
                    selector.unregister(pipe)
                    continue
                if pipe is process.stdout:
                    output += chunk
                    if len(output) > MAX_OUTPUT:
                        raise SSHError(
                            "administrative SSH response exceeded the output limit"
                        )
                else:
                    errors += chunk
                    del errors[:-131072]
                    if progress:
                        pending += chunk
                        while b"\n" in pending:
                            line, _, rest = pending.partition(b"\n")
                            pending = bytearray(rest)
                            if line.startswith(b"rsync-net: phase "):
                                phase = line[17:].decode(errors="replace")
                                if phase in PHASES:
                                    print(
                                        "rsync-net: phase " + phase,
                                        file=sys.stderr,
                                        flush=True,
                                    )
                        if len(pending) > 4096:
                            pending.clear()
        process.wait(timeout=max(0.01, deadline - time.monotonic()))
    return bytes(output), bytes(errors)


@contextlib.contextmanager
def invocation():
    existing = _CURRENT.get()
    if existing is not None:
        yield
        return
    state = {}
    token = _CURRENT.set(state)
    previous_handlers = {}
    terminating = False
    if threading.current_thread() is threading.main_thread():

        def terminate(signum, _frame):
            nonlocal terminating
            if not terminating:
                terminating = True
                raise SystemExit(128 + signum)

        for name in ("SIGTERM", "SIGHUP"):
            signum = getattr(signal, name, None)
            if signum is not None:
                previous_handlers[signum] = signal.getsignal(signum)
                signal.signal(signum, terminate)
    try:
        yield
    finally:
        terminating = True  # Further TERM/HUP must not interrupt bounded cleanup.
        try:
            if "session" in state:
                state["session"].close()
        finally:
            _CURRENT.reset(token)
            for signum, handler in previous_handlers.items():
                signal.signal(signum, handler)


@contextlib.contextmanager
def session(manifest, *, executable="ssh", fail_executable=None, **identity):
    settings = (
        json.dumps(manifest["connection"], sort_keys=True),
        executable,
        fail_executable,
        tuple(sorted((key, str(value)) for key, value in identity.items())),
    )
    current = _CURRENT.get()
    if current is None:
        with Session(
            manifest, executable=executable, fail_executable=fail_executable, **identity
        ) as connection:
            yield connection
        return
    if "session" not in current:
        current["settings"] = settings
        current["session"] = Session(
            manifest, executable=executable, fail_executable=fail_executable, **identity
        )
    if current["settings"] != settings:
        raise SSHError(
            "administrative identity or destination changed within one invocation"
        )
    yield current["session"]
