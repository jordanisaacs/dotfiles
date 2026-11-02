"""Exercise the transport with real subprocesses and a disposable mux wire."""

import json
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

import pytest
from test_planner import policy

from rsync_net import ssh

FAKE = r"""
import json, os, signal, socket, sys, time
from pathlib import Path
args = sys.argv[1:]
root = Path(os.environ["RSYNC_FAKE_SSH"])
control = Path(args[args.index("-S") + 1])
if "-M" in args:
    with (root / "auth").open("a") as stream:
        stream.write("authenticated\n")
    (root / "master.pid").write_text(str(os.getpid()))
    sock = socket.socket(socket.AF_UNIX)
    sock.bind(str(control))
    sock.listen()
    while True:
        connection, _ = sock.accept()
        connection.close()
proxy = next((x for x in args if x.startswith("ProxyCommand=")), "")
assert proxy.endswith("false"), args
try:
    sock = socket.socket(socket.AF_UNIX)
    sock.connect(str(control))
    sock.close()
except OSError:
    if not proxy:
        with (root / "auth").open("a") as stream:
            stream.write("UNEXPECTED FALLBACK AUTH\n")
    sys.exit(111)
(root / "child.pid").write_text(str(os.getpid()))
remote = args[-1]
if remote == "hang":
    time.sleep(30)
if remote == "drop":
    os.kill(int((root / "master.pid").read_text()), signal.SIGTERM)
    sys.exit(111)
if remote == "burst":
    sys.stderr.write("do-not-log-this-secret" * 100000 + "\n")
    sys.stderr.write("rsync-net: phase accounts\n")
    sys.stderr.flush()
payload = sys.stdin.read()
value = {"received": len(payload), "value": "x" * (2000000 if remote == "burst" else 0)}
print(json.dumps(value))
"""


@pytest.fixture
def wire(tmp_path, monkeypatch):
    executable = tmp_path / "fake-ssh"
    executable.write_text("#!" + sys.executable + "\n" + FAKE)
    executable.chmod(0o700)
    monkeypatch.setenv("RSYNC_FAKE_SSH", str(tmp_path))
    return executable, tmp_path


def connection(executable):
    return ssh.Session(
        policy(),
        executable=str(executable),
        admin_identity=Path("/selected/private-key"),
        known_hosts=Path("/pinned/hosts"),
    )


def authenticated(root):
    return (root / "auth").read_text().splitlines()


def test_one_authentication_shared_channels_and_private_cleanup(wire):
    executable, root = wire
    with connection(executable) as session:
        first = session.run("json", input="first")
        second = session.run("json", input="second")
        directory = session.socket.parent
        assert directory.stat().st_mode & 0o777 == 0o700
        assert json.loads(first.stdout)["received"] == 5
        assert json.loads(second.stdout)["received"] == 6
        assert authenticated(root) == ["authenticated"]
        assert "ControlMaster=yes" in session.master.args
        assert "ControlPersist=no" in session.master.args
        assert session.master.args[session.master.args.index("-F") + 1] == "/dev/null"
        assert "IdentityAgent=none" in session.master.args
        assert "StrictHostKeyChecking=yes" in session.master.args
        assert "GlobalKnownHostsFile=/dev/null" in session.master.args
    assert not directory.exists()
    assert session.master.poll() is not None


def test_invocation_lazily_shares_only_its_own_master(wire):
    executable, root = wire
    identity = {
        "executable": str(executable),
        "admin_identity": Path("/key"),
        "known_hosts": Path("/hosts"),
    }
    with ssh.invocation():
        assert not (root / "auth").exists()
        with ssh.session(policy(), **identity) as one:
            one.run("json")
        with ssh.session(policy(), **identity) as two:
            assert two is one
            two.run("json")
        socket = one.socket
    assert not socket.exists()
    with ssh.invocation(), ssh.session(policy(), **identity) as next_session:
        next_session.run("json")
    assert authenticated(root) == ["authenticated", "authenticated"]


def test_lost_master_never_reauthenticates_or_falls_back(wire):
    executable, root = wire
    with connection(executable) as session:
        session.run("json")
        session.master.terminate()
        session.master.wait(timeout=2)
        with pytest.raises(ssh.SSHError, match="lost"):
            session.run("json")
    assert authenticated(root) == ["authenticated"]


def test_drop_during_channel_cannot_trigger_fallback_authentication(wire):
    executable, root = wire
    with connection(executable) as session:
        result = session.run("drop")
        assert result.returncode == 111
        session.master.wait(timeout=2)
        with pytest.raises(ssh.SSHError, match="lost"):
            session.run("json")
    assert authenticated(root) == ["authenticated"]


def test_timeout_reaps_child_master_and_control_socket(wire):
    executable, root = wire
    with connection(executable) as session:
        with pytest.raises(subprocess.TimeoutExpired):
            session.run("hang", timeout=0.3)
        assert session.closed
        assert not session.socket.parent.exists()
        with pytest.raises(ProcessLookupError):
            os.kill(int((root / "child.pid").read_text()), 0)
        assert session.master.poll() is not None
    assert authenticated(root) == ["authenticated"]


def test_large_bidirectional_io_does_not_deadlock_or_log_payloads(wire, capsys):
    executable, root = wire
    with connection(executable) as session:
        result = session.run(
            "burst", input="private-envelope" * 150000, timeout=10, progress=True
        )
    assert json.loads(result.stdout)["received"] == len("private-envelope") * 150000
    assert len(json.loads(result.stdout)["value"]) == 2000000
    captured = capsys.readouterr()
    assert captured.out == ""
    assert captured.err == "rsync-net: phase accounts\n"
    assert authenticated(root) == ["authenticated"]


def test_identity_change_within_invocation_is_refused(wire):
    executable, root = wire
    with ssh.invocation():
        with ssh.session(
            policy(), executable=str(executable), admin_identity=Path("/key")
        ) as first:
            first.run("json")
        with (
            pytest.raises(ssh.SSHError, match="identity or destination changed"),
            ssh.session(
                policy(),
                executable=str(executable),
                admin_identity=Path("/different-key"),
            ),
        ):
            pass
    assert authenticated(root) == ["authenticated"]


def test_unicode_pinned_host_file_uses_literal_ssh_filename():
    arguments = ssh.command(
        policy(),
        known_hosts=Path("/keys/雪 pinned hosts"),
        admin_identity=Path("/private-key"),
    )
    option = next(
        value for value in arguments if value.startswith("UserKnownHostsFile=")
    )
    assert "雪" in option and "\\u" not in option
    assert '"/keys/雪 pinned hosts"' in option


def test_agent_backed_administration_allows_native_hardware_prompts():
    arguments = ssh.command(policy(), admin_agent_public_key=Path("/hardware-key.pub"))
    assert "BatchMode=no" in arguments
    assert "IdentityAgent=none" not in arguments
    assert "PreferredAuthentications=publickey" in arguments


@pytest.mark.parametrize("signum", [signal.SIGTERM, signal.SIGHUP])
def test_cli_termination_reaps_authenticated_master_and_private_socket(wire, signum):
    executable, root = wire
    worker = root / "controller.py"
    worker.write_text(
        "import json,sys,time\nfrom pathlib import Path\n"
        + "sys.path.insert(0,"
        + json.dumps(str(Path(ssh.__file__).parents[1]))
        + ")\n"
        + "from rsync_net import ssh\n"
        + "manifest="
        + repr(policy())
        + "\n"
        + "with ssh.invocation():\n"
        + "    with ssh.session(manifest,executable="
        + repr(str(executable))
        + ",admin_identity=Path('/key')) as connection:\n"
        + "        connection.run('json')\n"
        + "        Path("
        + repr(str(root / "ready.json"))
        + ").write_text(json.dumps({'socket':str(connection.socket),'pid':connection.master.pid}))\n"
        + "    time.sleep(30)\n"
    )
    controller = subprocess.Popen(
        [sys.executable, str(worker)], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    try:
        deadline = time.monotonic() + 5
        while not (root / "ready.json").exists():
            assert controller.poll() is None
            assert time.monotonic() < deadline
            time.sleep(0.01)
        details = json.loads((root / "ready.json").read_text())
        controller.send_signal(signum)
        stdout, stderr = controller.communicate(timeout=5)
        assert controller.returncode == 128 + signum, (stdout, stderr)
        assert not Path(details["socket"]).parent.exists()
        with pytest.raises(ProcessLookupError):
            os.kill(details["pid"], 0)
        assert authenticated(root) == ["authenticated"]
    finally:
        if controller.poll() is None:
            controller.kill()
            controller.wait()
        controller.stdout.close()
        controller.stderr.close()


def test_invocation_restores_handlers_and_is_safe_outside_main_thread():
    previous = {
        signum: signal.getsignal(signum) for signum in (signal.SIGTERM, signal.SIGHUP)
    }
    with ssh.invocation():
        assert all(
            signal.getsignal(signum) is not handler
            for signum, handler in previous.items()
        )
    assert all(
        signal.getsignal(signum) is handler for signum, handler in previous.items()
    )
    completed = threading.Event()

    def worker():
        with ssh.invocation():
            completed.set()

    thread = threading.Thread(target=worker)
    thread.start()
    thread.join(timeout=2)
    assert not thread.is_alive() and completed.is_set()
