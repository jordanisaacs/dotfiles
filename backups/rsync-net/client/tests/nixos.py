"""Check native system SSH settings, service jobs and daemon cache credentials."""

import csv
import json
import os
import shlex
import subprocess
from pathlib import Path
from urllib.parse import parse_qs, urlparse

data = json.loads(Path(os.environ["CLIENT_CONFIG"]).read_text())
config = Path("system-ssh-config")
config.write_text(data["ssh"])
for alias, user, identity in (
    ("rsync-net-database", "database", "/run/service secrets/ssh-key"),
    ("rsync-net-cache", "cache", "/run/cache secrets/root-ssh-key"),
):
    result = subprocess.check_output(["ssh", "-G", "-F", str(config), alias], text=True)
    ssh = dict(line.split(" ", 1) for line in result.splitlines())
    assert ssh["hostname"] == "custom.example.invalid"
    assert ssh["port"] == "2222"
    assert ssh["user"] == user and ssh["identityfile"] == identity
    assert ssh["identityagent"] == "none" and ssh["identitiesonly"] == "yes"
    assert ssh["addkeystoagent"] == "false" and ssh["forwardagent"] == "no"
    assert ssh["requesttty"] == "false"
    assert ssh.get("controlpath", "none") == "none"
    assert ssh["stricthostkeychecking"] == "true"
    assert ssh["hostkeyalias"] == "public.example.invalid"
    assert (
        "public.example.invalid ssh-ed25519 "
        in Path(ssh["userknownhostsfile"]).read_text()
    )

public_config = Path("public-ssh-config")
public_config.write_text(data["publicDefault"]["ssh"])
public_result = subprocess.check_output(
    ["ssh", "-G", "-F", str(public_config), "rsync-net-cache"], text=True
)
public_ssh = dict(line.split(" ", 1) for line in public_result.splitlines())
assert public_ssh["hostname"] == "public.example.invalid"
assert public_ssh["port"] == "22022"
public_arguments = shlex.split(data["publicDefault"]["service"]["ExecStart"][0])
public_option = next(
    next(csv.reader([value]))[0]
    for value in public_arguments
    if "rclone.program=" in value
)
public_argv = shlex.split(public_option.removeprefix("rclone.program="))
assert public_argv[-1] == "database@public.example.invalid"
assert public_argv[public_argv.index("-p") + 1] == "22022"

url = data["urls"]["private"]
parsed = urlparse(url)
assert parsed.scheme == "ssh" and parsed.username == "cache"
assert parsed.hostname == "rsync-net-cache"
query = parse_qs(parsed.query)
assert query["ssh-key"] == ["/run/cache secrets/root-ssh-key"]
assert "trusted" not in query and data["requireSigs"]
assert url in data["substituters"]
assert "https://cache.nixos.org/" in data["substituters"]
assert data["signingKey"] in data["keys"]
assert any(key.startswith("cache.nixos.org-1:") for key in data["keys"])
service = data["service"]
assert service["User"] == "root"
assert "--prune" not in " ".join(service["ExecStart"])
assert (
    data["environment"]["RESTIC_PASSWORD_FILE"]
    == "/run/service secrets/restic-password"
)
assert "SSH_AUTH_SOCK" not in data["environment"]
assert data["timer"]["Persistent"]
arguments = shlex.split(service["ExecStart"][0])
native_option = next(value for value in arguments if "rclone.program=" in value)
subprocess.check_output(["restic", "-o", native_option, "version"], text=True)
option = next(csv.reader([native_option]))[0]
ssh_args = shlex.split(option.removeprefix("rclone.program="))
assert ssh_args[ssh_args.index("-F") + 1] == "/dev/null"
assert ssh_args[ssh_args.index("-i") + 1] == "/run/service secrets/ssh-key"
assert "IdentityAgent=none" in ssh_args
print(
    "Native system SSH, independent service credentials and signed daemon-cache configuration pass"
)
