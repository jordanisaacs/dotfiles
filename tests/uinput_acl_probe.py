"""Reproduce retained uaccess ACLs using native ACL and tmpfiles tools in a VM."""

import json
import stat
import subprocess
from pathlib import Path


def run(*arguments, check=True):
    return subprocess.run(
        arguments, capture_output=True, text=True, check=check, timeout=15
    )


def probe():
    return run(
        "runuser",
        "-u",
        "xremap",
        "--",
        "python",
        "-c",
        "import os; fd=os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK); os.close(fd)",
        check=False,
    )


def main():
    node = Path("/dev/uinput")
    assert stat.S_ISCHR(node.stat().st_mode), "fixture must use the VM uinput device"
    run("setfacl", "--remove-all", str(node))
    run("chmod", "0600", str(node))
    run("setfacl", "--modify", "u:jd:rw,g::---,m::rw,o::---", str(node))
    before = run("getfacl", "--omit-header", str(node)).stdout
    assert "group::---" in before and "user:jd:rw-" in before, before
    assert stat.S_IMODE(node.stat().st_mode) == 0o660
    denied = probe()
    assert denied.returncode != 0 and "PermissionError" in denied.stderr, denied

    # Execute the actual production tmpfiles declaration, selected from the
    # evaluated module. The negative control supplies an empty file instead.
    run("systemd-tmpfiles", "--create", "/etc/uinput-acl-repair.conf")
    after = run("getfacl", "--omit-header", str(node)).stdout
    allowed = probe()
    assert allowed.returncode == 0, (
        "dedicated remapper cannot open uinput after recovery",
        after,
        allowed.stderr,
    )
    assert "group::rw-" in after and "user:jd:rw-" in after, after
    assert stat.S_IMODE(node.stat().st_mode) == 0o660
    print(
        json.dumps(
            {
                "retained_uaccess_acl_reproduced": True,
                "owning_group_access_restored": True,
                "existing_user_acl_preserved": True,
                "no_input_events_generated": True,
            }
        )
    )


if __name__ == "__main__":
    main()
