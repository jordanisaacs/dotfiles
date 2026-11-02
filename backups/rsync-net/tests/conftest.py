"""Require the native prerequisites instead of silently skipping regressions."""

import os
import shutil
from pathlib import Path

import pytest


def pytest_sessionstart(session):
    missing = [
        name
        for name in ("ssh-keygen", "nix-instantiate", "restic", "gpg", "gpgconf")
        if shutil.which(name) is None
    ]
    if not os.environ.get("RSYNC_NET_NIX_LIB"):
        missing.append("RSYNC_NET_NIX_LIB")
    if missing:
        raise pytest.UsageError(
            "Missing regression prerequisites: "
            + ", ".join(missing)
            + ". Run from the rsync-net Nix development shell."
        )


@pytest.fixture(autouse=True)
def nix_sandbox_root_metadata(request, monkeypatch):
    """Represent the daemon-owned sandbox root in the native crypto fixture.

    Nix maps only its builder UID into the user namespace; its host-root-owned
    filesystem root therefore appears unmapped. Normalize only that root's
    owner, never its modes, children, or the production permission checks.
    Actual filesystem ownership and restoration are also exercised by the VM.
    """
    build_root = os.environ.get("NIX_BUILD_TOP")
    if request.module.__name__ != "test_recovery" or not build_root:
        return
    if Path(build_root).stat().st_uid != os.getuid():
        return
    root_owner = Path("/").stat().st_uid
    mappings = [
        tuple(map(int, line.split()))
        for line in Path("/proc/self/uid_map").read_text().splitlines()
    ]
    if any(first <= root_owner < first + length for first, _, length in mappings):
        return

    native_path = type(Path())

    class SandboxRootPath(native_path):
        def stat(self, *args, **kwargs):
            info = super().stat(*args, **kwargs)
            if self == native_path("/"):
                fields = list(info)
                fields[4] = 0
                return os.stat_result(fields)
            return info

    monkeypatch.setattr(request.module.recovery, "Path", SandboxRootPath)
