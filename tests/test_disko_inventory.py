"""Evaluate Disko's generated configuration without opening or writing a disk."""

import json
import os
from pathlib import Path

data = json.loads(Path(os.environ["INVENTORY"]).read_text())
assert data["destroy"] is False
assert data["filesystems"]["/"]["device"] == "/dev/mapper/cryptroot"
assert data["filesystems"]["/"]["fsType"] == "ext4"
assert data["filesystems"]["/boot"]["fsType"] == "vfat"
assert "umask=0077" in data["filesystems"]["/boot"]["options"]
assert data["resumeDevice"] == "/dev/mapper/cryptswap"
assert data["swaps"] == [{"device": "/dev/mapper/cryptswap", "randomEncryption": False}]
assert set(data["luks"]) == {"cryptkey", "cryptroot", "cryptswap"}
for name, partition in [
    ("cryptkey", "key"),
    ("cryptswap", "swap"),
    ("cryptroot", "root"),
]:
    expected = "/dev/disk/by-partuuid/" + data["partitionUUIDs"][partition]
    assert data["luks"][name]["device"] == expected
assert data["luks"]["cryptkey"]["keyFile"] is None
assert data["luks"]["cryptroot"]["keyFile"] == "/dev/mapper/cryptkey"
assert data["luks"]["cryptswap"]["keyFile"] == "/dev/mapper/cryptkey"
print("Disko preserved existing layout semantics through evaluation only")
