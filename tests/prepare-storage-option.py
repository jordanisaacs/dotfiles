"""Migrate disposable QEMU fixture disks; this program refuses real hardware."""

import json
import os
import shutil
import subprocess
from pathlib import Path


def run(command, *arguments, **kwargs):
    return subprocess.run([CONFIG[command], *arguments], check=True, **kwargs)


if Path("/sys/class/dmi/id/sys_vendor").read_text().strip() != "QEMU":
    raise SystemExit("Storage fixture refuses to run outside QEMU")
for disk, mebibytes in (("vdb", 17), ("vdc", 128), ("vdd", 512)):
    sectors = int(Path(f"/sys/class/block/{disk}/size").read_text())
    if sectors != mebibytes * 2048:
        raise SystemExit(f"Refusing unexpected fixture disk: {disk}")

password = Path("/run/vm-fixture-password")
password.write_text("Vm-fixture-4caD9!r3-Passphrase")
password.chmod(0o600)


def format_luks(device, label, key):
    run(
        "cryptsetup",
        "luksFormat",
        "--batch-mode",
        "--type",
        "luks2",
        "--label",
        label,
        "--pbkdf",
        "pbkdf2",
        "--pbkdf-force-iterations",
        "1000",
        "--key-file",
        str(key),
        device,
    )


format_luks("/dev/vdb", "NIXKEY", password)
run("cryptsetup", "open", "--key-file", str(password), "/dev/vdb", "cryptkey")
raw_key = Path("/dev/mapper/cryptkey")
with raw_key.open("wb", buffering=0) as stream:
    stream.write(os.urandom(1024 * 1024))
    os.fsync(stream.fileno())

devices = [("/dev/vdc", "NIXSWAP", "cryptswap"), ("/dev/vdd", "NIXROOT", "cryptroot")]
for device, label, name in devices:
    format_luks(device, label, raw_key)
    run("cryptsetup", "open", "--key-file", str(raw_key), device, name)
run("mkfsRoot", "/dev/mapper/cryptroot")
run("mkswap", "/dev/mapper/cryptswap")
root = Path("/run/vm-root-filesystem")
root.mkdir()
run("mount", "/dev/mapper/cryptroot", str(root))
(root / "migration-sentinel").write_text(
    "Existing root data survived additive enrollment"
)
run("umount", str(root))

mode = CONFIG["mode"]
old_key = Path("/run/vm-fixture-old-key")
shutil.copyfile(raw_key, old_key)
old_key.chmod(0o600)

for device, _label, _name in devices:
    if mode == "password":
        environment = os.environ | {"NEWPASSWORD": password.read_text()}
        run(
            "cryptenroll",
            "--password",
            "--unlock-key-file=" + str(old_key),
            device,
            env=environment,
        )
        run(
            "cryptsetup",
            "open",
            "--test-passphrase",
            "--key-file",
            str(password),
            device,
        )
        # All original slots remain usable: this is an additive migration.
        run(
            "cryptsetup",
            "open",
            "--test-passphrase",
            "--key-file",
            str(old_key),
            device,
        )

if mode == "key-filesystem":
    small_key = Path("/run/vm-fixture-small-key")
    small_key.write_bytes(os.urandom(64))
    small_key.chmod(0o600)
    for device, _label, _name in devices:
        run(
            "cryptsetup",
            "luksAddKey",
            "--key-file",
            str(old_key),
            device,
            str(small_key),
        )
        run(
            "cryptsetup",
            "open",
            "--test-passphrase",
            "--key-file",
            str(small_key),
            device,
        )
        run(
            "cryptsetup",
            "open",
            "--test-passphrase",
            "--key-file",
            str(old_key),
            device,
        )
    # Only the disposable 1 MiB mapper payload is reformatted, after both new
    # credentials were verified. No partition resizing is needed.
    run("mkfsKey", "-F", "-m", "0", str(raw_key))
    mountpoint = Path("/run/vm-key-filesystem")
    mountpoint.mkdir()
    run("mount", str(raw_key), str(mountpoint))
    shutil.copyfile(small_key, mountpoint / "root.key")
    (mountpoint / "root.key").chmod(0o600)
    run("umount", str(mountpoint))

run("mount", "/dev/mapper/cryptroot", str(root))
sentinel = (root / "migration-sentinel").read_text()
assert sentinel == "Existing root data survived additive enrollment"
metadata = {}
for device, _label, name in devices:
    run("cryptsetup", "open", "--test-passphrase", "--key-file", str(old_key), device)
    result = run(
        "cryptsetup",
        "luksDump",
        "--dump-json-metadata",
        device,
        capture_output=True,
        text=True,
    )
    metadata[name] = sorted(json.loads(result.stdout)["keyslots"])
(root / "migration-keyslots.json").write_text(json.dumps(metadata))
run("umount", str(root))
