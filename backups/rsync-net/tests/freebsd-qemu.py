"""Start a real FreeBSD provider inside the native NixOS test-driver lifecycle.

The release image stays immutable. Each driver machine state directory owns its
OS overlay and separate ZFS disk, so a failed test cannot mutate a shared base
image or host block device. The driver supplies monitor, console and VLANs.
"""

import json
import os
import subprocess
import sys
from pathlib import Path


def main():
    settings = json.loads(Path(sys.argv[1]).read_text())
    state = Path.cwd()
    system_disk = state / "freebsd-system.qcow2"
    data_disk = state / "freebsd-data.qcow2"
    if not system_disk.exists():
        subprocess.run(
            [
                settings["qemuImg"],
                "create",
                "-f",
                "qcow2",
                "-F",
                "qcow2",
                "-b",
                settings["image"],
                str(system_disk),
            ],
            check=True,
        )
    if not data_disk.exists():
        subprocess.run(
            [settings["qemuImg"], "create", "-f", "qcow2", str(data_disk), "2G"],
            check=True,
        )
    arguments = [
        settings["qemu"],
        "-machine",
        "accel=kvm",
        "-cpu",
        "host",
        "-m",
        "1536",
        "-smp",
        "2",
        "-drive",
        f"file={system_disk},format=qcow2,if=virtio",
        "-drive",
        f"file={data_disk},format=qcow2,if=virtio",
        "-drive",
        f"file={settings['seed']},format=raw,media=cdrom,readonly=on",
        "-drive",
        f"file={settings['packages']},format=raw,if=virtio,readonly=on",
        "-device",
        "virtio-net-pci,netdev=admin,mac=52:54:00:12:01:02",
        "-netdev",
        "vde,id=admin,sock=" + os.environ["QEMU_VDE_SOCKET_1"],
        *sys.argv[2:],
    ]
    os.execv(arguments[0], arguments)


if __name__ == "__main__":
    main()
