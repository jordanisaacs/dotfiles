"""Exercise generated native SSH, Git and user-service configuration."""

import csv
import json
import os
import shlex
import subprocess
from pathlib import Path

data = json.loads(Path(os.environ["CLIENT_CONFIG"]).read_text())
home = Path(data["homePath"])
home.mkdir(mode=0o700, parents=True)


def run(*arguments, **kwargs):
    return subprocess.check_output(arguments, text=True, **kwargs).strip()


ssh = dict(
    line.split(" ", 1)
    for line in run("ssh", "-G", "-F", data["ssh"], "rsync-net-files").splitlines()
)
assert ssh["hostname"] == "custom.example.invalid"
assert ssh["port"] == "2222"
assert ssh["user"] == "files"
assert ssh["identityagent"] == "none"
assert ssh["identitiesonly"] == "yes"
assert ssh["addkeystoagent"] == "false"
assert ssh["forwardagent"] == "no"
assert ssh["requesttty"] == "false"
assert ssh["stricthostkeychecking"] == "true"
assert ssh["hostkeyalias"] == "public.example.invalid"
assert ssh.get("controlpath", "none") == "none"
assert ssh["controlpersist"] == "no"
assert ssh["identityfile"] == str(home / ".local/state/rsync-net/keys/files")
assert len(ssh["userknownhostsfile"].split()) == 1
assert (
    "public.example.invalid ssh-ed25519 " in Path(ssh["userknownhostsfile"]).read_text()
)
assert "PRIVATE KEY" not in Path(data["publicSource"]).read_text()
runtime_trust = dict(
    line.split(" ", 1)
    for line in run(
        "ssh", "-G", "-F", data["runtimeTrustSsh"], "rsync-net-files"
    ).splitlines()
)
assert runtime_trust["userknownhostsfile"] == str(home / "trust/known hosts")

public_ssh = dict(
    line.split(" ", 1)
    for line in run(
        "ssh", "-G", "-F", data["publicDefault"]["ssh"], "rsync-net-files"
    ).splitlines()
)
assert public_ssh["hostname"] == "public.example.invalid"
assert public_ssh["port"] == "22022"
public_command = next(
    csv.reader(shlex.split(data["publicDefault"]["restic"]["extraOptions"][0]))
)[0]
public_argv = shlex.split(public_command.removeprefix("rclone.program="))
assert public_argv[-1] == "files@public.example.invalid"
assert public_argv[public_argv.index("-p") + 1] == "22022"

restic = data["restic"]
assert restic["paths"] == [str(home / "Documents two"), str(home / "Pictures")]
assert not restic["initialize"] and not restic["pruneOpts"]
assert restic["passwordFile"] == str(home / "secrets/restic-password")
native_option = shlex.split(restic["extraOptions"][0])[0]
descriptor = json.loads(Path(data["backupDescriptor"]).read_text())
assert descriptor["principal"] == "files"
assert descriptor["paths"] == restic["paths"]
assert descriptor["passwordFile"] == restic["passwordFile"]
assert descriptor["resticOptions"][0] == native_option
assert descriptor["manifest"]["recovery"]["recipients"] == [data["recovery"]]
# Exercise Restic's native CSV flag parser; shell/SSH parsing alone missed
# embedded filename quotes and allowed unusable generated backup jobs.
run("restic", "-o", native_option, "version")
command = next(csv.reader([native_option]))[0].removeprefix("rclone.program=")
argv = shlex.split(command)
assert argv[argv.index("-F") + 1] == "/dev/null"
assert argv[argv.index("-i") + 1] == str(home / ".local/state/rsync-net/keys/files")
assert argv[-1] == "files@custom.example.invalid"
assert "IdentityAgent=none" in argv and "StrictHostKeyChecking=yes" in argv
service = data["service"]["Service"]
environment = dict(
    item.split("=", 1)
    for entry in service["Environment"]
    for item in shlex.split(entry)
)
assert environment["RESTIC_PASSWORD_FILE"] == restic["passwordFile"]
assert "--prune" not in " ".join(service["ExecStart"])
assert data["timer"]["Timer"]["Persistent"]

env = dict(os.environ, GIT_CONFIG_GLOBAL=data["git"], GIT_CONFIG_NOSYSTEM="1")
repo = home / "src/project"
other = home / "src/other"
for path in (repo, other):
    path.mkdir(parents=True)
    run("git", "init", "-q", str(path), env=env)
assert run("git", "-C", str(repo), "remote", env=env) == ""
run(
    "git",
    "-C",
    str(repo),
    "remote",
    "add",
    "backup",
    "gcrypt::rsync://personal@rsync-net-personal/project",
    env=env,
)
participants = run(
    "git",
    "-C",
    str(repo),
    "config",
    "--get",
    "gcrypt.participants",
    env=env,
)
assert set(participants.split()) == {data["member"], data["recovery"]}
assert (
    run(
        "git",
        "-C",
        str(repo),
        "config",
        "--get",
        "user.signingkey",
        env=env,
    )
    == data["member"]
)
assert (
    subprocess.run(
        ["git", "-C", str(other), "config", "--get", "remote.backup.url"],
        env=env,
        capture_output=True,
        check=False,
    ).returncode
    == 1
)
print(
    "Generated SSH isolation, selected XDG backup paths, native user units and scoped Git recovery participants pass"
)
