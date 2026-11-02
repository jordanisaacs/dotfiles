"""Exercise the installed entry point/resources and package-free SSH envelope."""

import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest
from test_planner import policy

from rsync_net import cli as rsync_net


def test_installed_console_works_outside_the_checkout(tmp_path):
    command = shutil.which("rsync-net")
    assert command is not None
    manifest = tmp_path / "manifest.json"
    manifest.write_text(json.dumps(policy()))
    result = subprocess.run(
        [command, "--manifest", str(manifest), "validate"],
        cwd=tmp_path,
        env=dict(os.environ, PYTHONPATH=""),
        capture_output=True,
        text=True,
        timeout=30,
        check=True,
    )
    validated = json.loads(result.stdout)
    assert validated["valid"]
    assert validated["privateCaches"] == ["nix-cache"]
    module = subprocess.run(
        [sys.executable, "-m", "rsync_net", "--manifest", str(manifest), "validate"],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        timeout=30,
        check=True,
    )
    assert json.loads(module.stdout) == validated
    default = subprocess.run(
        [command, "validate"],
        cwd=tmp_path,
        env=dict(os.environ, PYTHONPATH=""),
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    if rsync_net.CONFIG.get("manifest"):
        assert default.returncode == 0, default.stderr
        assert json.loads(default.stdout)["valid"]
    else:
        assert default.returncode == 2
        assert "--manifest is required" in default.stderr


@pytest.mark.parametrize(
    "operation",
    [
        "--help",
        "_setup-review",
        "_setup",
        "_reconstruct",
        "_storage-review",
        "_storage-init",
        "_snapshots-review",
        "_snapshots-configure",
    ],
)
def test_ssh_controller_loads_without_the_python_package(tmp_path, operation):
    if operation != "--help" and sys.platform != "linux":
        pytest.skip("the package-free native-host rejection probe requires Linux")
    captured = {}

    def capture(manifest, remote, **options):
        captured["command"] = [remote]
        captured["input"] = options["input"]
        return subprocess.CompletedProcess([remote], 0, "{}", "")

    with patch.object(rsync_net, "remote_run", side_effect=capture):
        rsync_net.remote_call(
            policy(), operation, admin_identity=Path("/explicit/admin-identity")
        )
    envelope = json.loads(captured["input"])
    assert set(envelope["helpers"]) == {
        "apply",
        "control",
        "setup",
        "storage",
        "snapshots",
        "sshdPolicy",
        "sshdTemplate",
    }
    # Isolated Python ignores both the checkout and installed site packages.
    # --help only parses; the native operations load embedded helpers and
    # reject Linux before any lock, inspection or mutation can run.
    launcher = shlex.split(captured["command"][-1])[-1]
    result = subprocess.run(
        [sys.executable, "-I", "-S", "-c", launcher],
        cwd=tmp_path,
        input=captured["input"],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    if operation == "--help":
        assert result.returncode == 0, result.stderr
        assert "administrative" in result.stdout
        assert result.stdout.startswith("usage: rsync-net ")
    else:
        assert result.returncode == 2, result.stderr
        assert "requires FreeBSD" in result.stderr


def test_linux_local_inspection_and_state_are_refused_before_native_commands():
    with (
        patch.object(rsync_net.platform, "system", return_value="Linux"),
        patch.object(rsync_net, "run_readonly") as native,
        pytest.raises(rsync_net.PolicyError, match="native FreeBSD"),
    ):
        rsync_net.inspect_local(policy())
    native.assert_not_called()
    with pytest.raises(rsync_net.PolicyError, match="native FreeBSD"):
        rsync_net.plan(policy(), {"schemaVersion": 1, "system": "Linux"})
