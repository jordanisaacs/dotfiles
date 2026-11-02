"""Format only a small disposable QEMU disk using upstream Disko builders."""

import json
import subprocess
from pathlib import Path


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


def main() -> None:
    if Path("/sys/class/dmi/id/sys_vendor").read_text().strip() != "QEMU":
        raise SystemExit("Refusing to provision storage outside QEMU")
    disk = json.loads(
        run(CONFIG["lsblk"], "--json", "--bytes", "--output", "PATH,SIZE", "/dev/vdb")
    )
    assert disk["blockdevices"] == [{"path": "/dev/vdb", "size": 1073741824}], disk
    secret = Path("/run/disko-vm-password")
    secret.touch(mode=0o600)
    secret.write_text("Public-VM-fixture-password-only")
    subprocess.run([CONFIG["format"]], check=True)
    subprocess.run([CONFIG["mount"]], check=True)
    mounted = json.loads(
        run(
            CONFIG["findmnt"],
            "--json",
            "--output",
            "TARGET,SOURCE,FSTYPE",
            "--submounts",
            "/mnt",
        )
    )
    root = mounted["filesystems"][0]
    assert root["target"] == "/mnt", root
    assert root["source"] == "/dev/mapper/cryptroot", root
    assert root["fstype"] == "ext4", root
    boot = root["children"][0]
    assert boot["target"] == "/mnt/boot", boot
    assert boot["source"] == "/dev/vdb1", boot
    assert boot["fstype"] == "vfat", boot
    assert Path("/mnt/boot").stat().st_mode & 0o777 == 0o700
    Path("/mnt/provisioning-sentinel").write_text("Declaratively provisioned VM root")
    for device, label in (
        ("/dev/vdb3", "NIXROOT"),
        ("/dev/vdb2", "NIXSWAP"),
    ):
        metadata = json.loads(
            run(CONFIG["cryptsetup"], "luksDump", "--dump-json-metadata", device)
        )
        assert len(metadata["keyslots"]) == 1, metadata
        actual_label = run(
            CONFIG["blkid"], "--match-tag", "LABEL", "--output", "value", device
        )
        assert actual_label == label
        subprocess.run(
            [
                CONFIG["cryptsetup"],
                "open",
                "--test-passphrase",
                "--key-file",
                str(secret),
                device,
            ],
            check=True,
        )
    subprocess.run([CONFIG["umount"], "--recursive", "/mnt"], check=True)
    # A fresh open proves the persistent volume key, not merely an old mapper.
    subprocess.run([CONFIG["cryptsetup"], "close", "cryptroot"], check=True)
    subprocess.run(
        [
            CONFIG["cryptsetup"],
            "open",
            "--key-file",
            str(secret),
            "/dev/vdb3",
            "cryptroot",
        ],
        check=True,
    )
    subprocess.run([CONFIG["mountBin"], "/dev/mapper/cryptroot", "/mnt"], check=True)
    sentinel = Path("/mnt/provisioning-sentinel").read_text()
    assert sentinel == "Declaratively provisioned VM root"


if __name__ == "__main__":
    main()
