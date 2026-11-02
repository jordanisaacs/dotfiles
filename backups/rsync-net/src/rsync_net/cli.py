"""Enroll device identities and reconstruct narrowly managed rsync.net policy.

The manifest contains public policy only. Privileged account/config restoration
requires explicit administrative SSH and a saved, freshly matched review. The
storage init creates only reviewed missing ZFS filesystems. Server prerequisites
and per-backup account bootstrap are separate reviewed operations.
"""

import argparse
import base64
import hashlib
import importlib.util
import json
import os
import platform
import re
import shlex
import stat
import struct
import subprocess
import sys
from importlib.resources import files
from pathlib import Path, PurePosixPath

if "REMOTE_MANIFEST" in globals():
    # The SSH envelope embeds provider helpers; no Python package is installed.
    CONFIG = {}
else:
    from rsync_net.data import CONFIG

NAME = re.compile(r"[a-z][a-z0-9_-]{0,30}\Z")
DATASET = re.compile(r"[A-Za-z0-9_.:-]+(?:/[A-Za-z0-9_.:-]+)*\Z")
PATH = re.compile(r"/[A-Za-z0-9_./-]+\Z")
BACKENDS = {"restic", "git", "nix-cache"}


def asset(kind):
    embedded = globals().get("REMOTE_HELPERS", {}).get(kind)
    if embedded is not None:
        return embedded
    filename = {
        "sshdPolicy": "private-sshd-policy.json",
        "sshdTemplate": "private-sshd.conf.in",
    }[kind]
    return files("rsync_net.data").joinpath(filename).read_text()


PRIVATE_POLICY = json.loads(asset("sshdPolicy"))
AUTHORIZATION_ROOT = Path(PRIVATE_POLICY["authorizedKeysRoot"])
PRIVATE_SSHD_CONFIG = Path(PRIVATE_POLICY["configPath"])


class PolicyError(ValueError):
    """Invalid or unsafe manifest/state."""


def require(condition, message):
    if not condition:
        raise PolicyError(message)


def fields(value, expected, label):
    require(isinstance(value, dict), f"{label} must be an object")
    require(set(value) == set(expected), f"unexpected/missing fields in {label}")


def unique(values, label):
    require(len(values) == len(set(values)), f"duplicate {label}")


def safe_path(value, label):
    require(isinstance(value, str) and PATH.fullmatch(value), f"invalid {label}")
    require(".." not in PurePosixPath(value).parts, f"parent traversal in {label}")
    require(str(PurePosixPath(value)) == value, f"non-canonical {label}")


def validate_recovery(policy, label, *, backend=None):
    fields(policy, {"enable", "recipients"}, label)
    require(type(policy["enable"]) is bool, f"{label} enable must be boolean")
    require(
        isinstance(policy["recipients"], list), f"{label} recipients must be a list"
    )
    for recipient in policy["recipients"]:
        require(
            isinstance(recipient, str)
            and re.fullmatch(r"[A-F0-9]{40}|[A-F0-9]{64}", recipient),
            f"{label} requires full uppercase public OpenPGP fingerprints",
        )
    require(
        not policy["enable"] or bool(policy["recipients"]),
        f"{label} is enabled without public recipients",
    )
    require(
        backend != "nix-cache" or not policy["enable"],
        "static cache data has no recovery decryption key",
    )


def validate_snapshot_cron(value):
    require(
        isinstance(value, str) and re.fullmatch(r"[0-9*,/-]+(?: [0-9*,/-]+){4}", value),
        "snapshot schedule must be five numeric cron fields",
    )
    for field, (low, high) in zip(
        value.split(" "), ((0, 59), (0, 23), (1, 31), (1, 12), (0, 7)), strict=True
    ):
        for item in field.split(","):
            pieces = item.split("/")
            require(1 <= len(pieces) <= 2, "invalid snapshot cron step")
            base = pieces[0]
            if len(pieces) == 2:
                require(
                    pieces[1].isdigit()
                    and 0 < int(pieces[1]) <= high - low + 1
                    and (base == "*" or "-" in base),
                    "invalid snapshot cron step",
                )
            if base == "*":
                continue
            bounds = base.split("-")
            require(
                1 <= len(bounds) <= 2 and all(n.isdigit() for n in bounds),
                "invalid snapshot cron range",
            )
            numbers = list(map(int, bounds))
            require(
                all(low <= n <= high for n in numbers) and numbers[0] <= numbers[-1],
                "snapshot cron value out of range",
            )


def validate(manifest):
    require(isinstance(manifest, dict), "manifest must be an object")
    # Older public enrollment records predate the optional setup workflow.
    manifest.setdefault("mode", "public")
    manifest.setdefault("setup", {"enable": False, "expectedRelease": None})
    fields(
        manifest,
        {
            "schemaVersion",
            "mode",
            "setup",
            "connection",
            "pool",
            "principals",
            "datasets",
            "control",
            "recovery",
        },
        "manifest",
    )
    require(manifest["schemaVersion"] == 1, "unsupported manifest schema")
    require(
        isinstance(manifest["mode"], str) and manifest["mode"] in {"public", "private"},
        "invalid server mode",
    )
    setup = manifest["setup"]
    setup.setdefault("backends", ["restic"])
    setup.setdefault("snapshotting", False)
    fields(setup, {"enable", "expectedRelease", "backends", "snapshotting"}, "setup")
    require(type(setup["snapshotting"]) is bool, "setup snapshotting must be boolean")
    require(
        isinstance(setup["backends"], list)
        and all(isinstance(b, str) and b in BACKENDS for b in setup["backends"]),
        "invalid server setup backends",
    )
    unique(setup["backends"], "server setup backend")
    require(type(setup["enable"]) is bool, "setup enable must be boolean")
    require(
        setup["expectedRelease"] is None
        or (
            isinstance(setup["expectedRelease"], str)
            and re.fullmatch(
                r"[0-9]+\.[0-9]+-RELEASE(?:-p[0-9]+)?", setup["expectedRelease"]
            )
        ),
        "invalid approved FreeBSD release",
    )
    validate_recovery(manifest["recovery"], "default recovery")
    connection = manifest["connection"]
    fields(connection, {"host", "user", "port", "interpreter"}, "connection")
    require(
        isinstance(connection["host"], str)
        and re.fullmatch(r"[A-Za-z0-9.-]+", connection["host"]),
        "invalid SSH host",
    )
    require(
        isinstance(connection["user"], str) and NAME.fullmatch(connection["user"]),
        "invalid SSH user",
    )
    require(
        type(connection["port"]) is int and 0 < connection["port"] < 65536,
        "invalid SSH port",
    )
    safe_path(connection["interpreter"], "interpreter path")
    pool = manifest["pool"]
    fields(pool, {"name", "guid"}, "pool")
    require(
        isinstance(pool["name"], str)
        and DATASET.fullmatch(pool["name"])
        and "/" not in pool["name"],
        "invalid pool name",
    )
    require(
        pool["guid"] is None
        or (isinstance(pool["guid"], str) and pool["guid"].isdigit()),
        "invalid pool GUID",
    )
    principals = manifest["principals"]
    datasets = manifest["datasets"]
    require(
        isinstance(principals, list) and isinstance(datasets, list),
        "principals and datasets must be lists",
    )
    for principal in principals:
        fields(
            principal,
            {
                "name",
                "uid",
                "gid",
                "home",
                "backend",
                "dataset",
                "publicKeys",
                "readOnlyKeys",
                "gcryptParticipants",
                "recovery",
                "cache",
            },
            "principal",
        )
        require(
            isinstance(principal["name"], str)
            and NAME.fullmatch(principal["name"])
            and principal["name"] != "root",
            "invalid managed principal",
        )
        for field in ("uid", "gid"):
            value = principal[field]
            require(
                value is None or (type(value) is int and 1000 <= value < 2147483647),
                f"invalid reserved {field}",
            )
        safe_path(principal["home"], "principal home")
        require(
            principal["home"] == f"/home/{principal['name']}",
            "managed home must be /home/<principal>",
        )
        require(principal["backend"] in BACKENDS, "invalid principal backend")
        validate_recovery(
            principal["recovery"], "principal recovery", backend=principal["backend"]
        )
        require(
            principal["dataset"] is None or isinstance(principal["dataset"], str),
            "invalid principal dataset",
        )
        require(isinstance(principal["publicKeys"], list), "publicKeys must be a list")
        for key in principal["publicKeys"]:
            require(
                isinstance(key, str)
                and re.fullmatch(
                    r"(?:ssh-ed25519|sk-ssh-ed25519@openssh.com) [A-Za-z0-9+/]+={0,2}(?: [^\r\n]+)?",
                    key,
                ),
                "only bare Ed25519 public keys are accepted",
            )
            try:
                wire = base64.b64decode(key.split()[1], validate=True)
                algorithm_length = struct.unpack("!I", wire[:4])[0]
                algorithm = wire[4 : 4 + algorithm_length].decode("ascii")
                require(
                    algorithm == key.split()[0],
                    "public key algorithm differs from its encoding",
                )
                key_length = struct.unpack(
                    "!I", wire[4 + algorithm_length : 8 + algorithm_length]
                )[0]
                require(
                    key_length == 32 and len(wire) >= 8 + algorithm_length + 32,
                    "invalid Ed25519 public key",
                )
                if algorithm == "ssh-ed25519":
                    require(
                        len(wire) == 8 + algorithm_length + 32,
                        "unexpected public key trailing data",
                    )
            except (ValueError, struct.error) as error:
                raise PolicyError("invalid public key encoding") from error
        unique(principal["publicKeys"], "public key in principal")
        require(
            isinstance(principal["readOnlyKeys"], list), "readOnlyKeys must be a list"
        )
        unique(principal["readOnlyKeys"], "read-only public key in principal")
        require(
            all(key in principal["publicKeys"] for key in principal["readOnlyKeys"]),
            "readOnlyKeys must be a subset of publicKeys",
        )
        require(
            principal["backend"] != "restic" or not principal["readOnlyKeys"],
            "Restic devices use append-only access; read-only membership is unsupported",
        )
        memberships = {}
        for key in principal["publicKeys"]:
            identity = " ".join(key.split()[:2])
            read_only = key in principal["readOnlyKeys"]
            require(
                identity not in memberships or memberships[identity] == read_only,
                "the same SSH key cannot have conflicting read-only permissions",
            )
            memberships[identity] = read_only
        require(
            isinstance(principal["gcryptParticipants"], list),
            "gcryptParticipants must be a list",
        )
        for fingerprint in principal["gcryptParticipants"]:
            require(
                isinstance(fingerprint, str)
                and re.fullmatch(r"[A-F0-9]{40}|[A-F0-9]{64}", fingerprint),
                "GPG membership requires full uppercase public fingerprints",
            )
        require(
            principal["backend"] == "git" or not principal["gcryptParticipants"],
            "only Git principals have gcrypt participants",
        )
        if principal["backend"] == "git" and principal["recovery"]["enable"]:
            require(
                set(principal["recovery"]["recipients"]).issubset(
                    principal["gcryptParticipants"]
                ),
                "Git participant policy omits enabled recovery recipients",
            )
    unique([p["name"] for p in principals], "principal name")
    for field in ("uid", "gid"):
        unique(
            [p[field] for p in principals if p[field] is not None], f"reserved {field}"
        )
    principal_names = {p["name"] for p in principals}
    for dataset in datasets:
        dataset.setdefault("snapshots", {})
        fields(
            dataset,
            {"name", "mountpoint", "principal", "purpose", "quotaBytes", "snapshots"},
            "dataset",
        )
        require(
            isinstance(dataset["name"], str) and DATASET.fullmatch(dataset["name"]),
            "invalid dataset name",
        )
        require(
            dataset["name"].startswith(pool["name"] + "/"),
            "managed dataset must be below expected pool",
        )
        safe_path(dataset["mountpoint"], "dataset mountpoint")
        require(
            dataset["mountpoint"] == "/mnt/" + dataset["name"],
            "mountpoint must match /mnt/<dataset>",
        )
        require(
            dataset["principal"] in principal_names, "dataset has undeclared principal"
        )
        require(
            dataset["purpose"] in {"user", "service", "git", "cache"},
            "invalid dataset purpose",
        )
        quota = dataset["quotaBytes"]
        require(quota is None or (type(quota) is int and quota > 0), "invalid quota")
        require(
            isinstance(dataset["snapshots"], dict),
            "snapshot schedules must be an object",
        )
        for label, schedule in dataset["snapshots"].items():
            require(
                isinstance(label, str) and re.fullmatch(r"[a-z][a-z0-9-]{0,30}", label),
                "invalid snapshot schedule label",
            )
            fields(schedule, {"schedule", "retention"}, "snapshot schedule")
            require(
                isinstance(schedule["retention"], str)
                and re.fullmatch(
                    r"forever|[1-9][0-9]*[sMhdwmy]", schedule["retention"]
                ),
                "invalid snapshot retention",
            )
            validate_snapshot_cron(schedule["schedule"])
    unique([d["name"] for d in datasets], "dataset name")
    unique([d["mountpoint"] for d in datasets], "dataset mountpoint")
    for a in datasets:
        for b in datasets:
            require(
                a is b or not b["name"].startswith(a["name"] + "/"),
                "managed repository datasets must not contain one another",
            )
    dataset_names = {d["name"] for d in datasets}
    for principal in principals:
        require(
            principal["dataset"] is None or principal["dataset"] in dataset_names,
            "principal has undeclared dataset",
        )
        if principal["dataset"] is not None:
            leaf = next(d for d in datasets if d["name"] == principal["dataset"])
            require(
                leaf["principal"] == principal["name"],
                "principal cannot claim another principal's dataset",
            )
            purpose = {
                "restic": {"user", "service"},
                "git": {"git"},
                "nix-cache": {"cache"},
            }[principal["backend"]]
            require(
                leaf["purpose"] in purpose,
                "principal backend differs from dataset purpose",
            )
    for principal in principals:
        cache = principal["cache"]
        if principal["backend"] != "nix-cache":
            require(cache is None, "cache settings require the nix-cache backend")
            continue
        fields(cache, {"signingPublicKeys"}, "principal cache")
        require(
            isinstance(cache["signingPublicKeys"], list),
            "cache signingPublicKeys must be a list",
        )
        for key in cache["signingPublicKeys"]:
            require(
                isinstance(key, str)
                and re.fullmatch(r"[A-Za-z0-9._-]+:[A-Za-z0-9+/]{43}=", key),
                "invalid Nix public signing key",
            )
    control = manifest["control"]
    control.setdefault("dataset", None)
    control.setdefault("quotaBytes", None)
    fields(control, {"enable", "path", "dataset", "quotaBytes"}, "control")
    require(
        control["dataset"] is None
        or (
            isinstance(control["dataset"], str)
            and DATASET.fullmatch(control["dataset"])
            and control["dataset"].startswith(pool["name"] + "/")
            and all(part not in {".", ".."} for part in control["dataset"].split("/"))
        ),
        "invalid control dataset",
    )
    require(
        control["quotaBytes"] is None
        or (type(control["quotaBytes"]) is int and control["quotaBytes"] > 0),
        "invalid control quota",
    )
    require(type(control["enable"]) is bool, "control enable must be boolean")
    if control["path"] is not None:
        safe_path(control["path"], "control path")
        require(
            len(PurePosixPath(control["path"]).parts) >= 3,
            "control path must be a dedicated directory",
        )
        for dataset in datasets:
            a, b = PurePosixPath(control["path"]), PurePosixPath(dataset["mountpoint"])
            require(
                not (a == b or a in b.parents or b in a.parents),
                "control path must be separate from every repository/cache",
            )
    return manifest


def backend_config(principal):
    if principal["backend"] != "restic":
        return None
    return (
        Path(principal["home"]) / ".rclone.conf",
        "# Managed by rsync-net; no credentials.\n[repository]\ntype = local\n",
    )


def legacy_authorization(manifest, principal):
    """Only the exact former append-only command, with the same enrolled keys."""
    if principal["backend"] != "restic":
        return ""
    dataset = next(d for d in manifest["datasets"] if d["name"] == principal["dataset"])
    command = f"/usr/local/bin/rclone serve restic --stdio --append-only {dataset['mountpoint']}"
    return "".join(
        f'restrict,command="{command}" {key}\n' for key in principal["publicKeys"]
    )


def authorization(manifest, principal):
    """Fixed per-principal commands for the existing provider SSH listener."""
    dataset = next(d for d in manifest["datasets"] if d["name"] == principal["dataset"])
    path = dataset["mountpoint"]
    commands = []
    for key in principal["publicKeys"]:
        read_only = key in principal["readOnlyKeys"]
        command = {
            "restic": f"/usr/local/bin/rclone --config {principal['home']}/.rclone.conf serve restic --stdio --append-only repository:{path}",
            "git": f"{manifest['connection']['interpreter']} -I -S /usr/local/sbin/rrsync {'-ro ' if read_only else ''}-munge {path}",
            "nix-cache": (
                "/usr/local/bin/nix-store --serve "
                + ("" if read_only else "--write ")
                + f"--store file://{path} --option builders ''"
            ),
        }[principal["backend"]]
        commands.append(f'restrict,command="{command}" {key}\n')
    return "".join(commands)


def authorization_path(principal):
    return Path(principal["home"]) / ".ssh/authorized_keys"


def scoped_principal(manifest, name):
    """Project one declared identity/storage boundary for bounded bootstrap."""
    principal = next((p for p in manifest["principals"] if p["name"] == name), None)
    require(principal is not None, "unknown bootstrap principal")
    return {
        **manifest,
        "principals": [principal],
        "datasets": [d for d in manifest["datasets"] if d["principal"] == name],
    }


def load_helper(kind):
    embedded = globals().get("REMOTE_HELPERS", {}).get(kind)
    source = Path(
        Path(__file__).parent
        / {
            "enrollment": "enrollment.py",
            "apply": "apply.py",
            "recovery": "recovery.py",
            "control": "control.py",
            "setup": "setup.py",
            "storage": "storage.py",
            "backup": "backup.py",
            "snapshots": "snapshots.py",
            "git": "git.py",
        }[kind]
    )
    spec = importlib.util.spec_from_file_location("rsync_net." + kind, source)
    require(
        spec is not None and spec.loader is not None, "controller helper is unavailable"
    )
    helper = importlib.util.module_from_spec(spec)
    if embedded is not None:
        # Trusted helper source arrives only over the administrative SSH channel.
        exec(compile(embedded, "rsync_net/" + kind + ".py", "exec"), helper.__dict__)  # noqa: S102
    else:
        spec.loader.exec_module(helper)
    return helper


def private_sshd_config(manifest):
    names = " ".join(sorted(p["name"] for p in manifest["principals"]))
    require(bool(names), "private daemon requires explicitly declared principals")
    values = {
        "listen_address": PRIVATE_POLICY["listenAddress"],
        "port": str(PRIVATE_POLICY["port"]),
        "pid_file": PRIVATE_POLICY["pidFile"],
        "host_key": PRIVATE_POLICY["hostKey"],
        "authorized_keys_root": str(AUTHORIZATION_ROOT),
        "managed_users": names,
    }
    content = asset("sshdTemplate")
    for placeholder, value in values.items():
        content = content.replace("@" + placeholder + "@", value)
    return content


def plan_digest(manifest, result):
    return hashlib.sha256(
        json.dumps(
            {"manifest": manifest, "plan": result},
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
    ).hexdigest()


def metadata(path, *, hash_contents=False):
    try:
        st = path.lstat()
    except FileNotFoundError:
        return {"exists": False}
    result = {
        "exists": True,
        "uid": st.st_uid,
        "gid": st.st_gid,
        "mode": stat.S_IMODE(st.st_mode),
        "symlink": stat.S_ISLNK(st.st_mode),
    }
    if hash_contents and stat.S_ISREG(st.st_mode):
        result["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def run_readonly(arguments):
    result = subprocess.run(
        arguments, capture_output=True, text=True, timeout=30, check=False
    )
    require(
        result.returncode == 0,
        f"inspection failed: {arguments[0]} (exit {result.returncode})",
    )
    return result.stdout


def active_processes(managed_uids):
    """Use native BSD per-column formatting; malformed output is never empty."""
    output = run_readonly(
        ["/bin/ps", "-axww", "-o", "uid=", "-o", "pid=", "-o", "comm="]
    )
    processes = []
    for row in output.splitlines():
        if not row.strip():
            continue
        values = row.split(None, 2)
        require(
            len(values) == 3 and values[0].isdigit() and values[1].isdigit(),
            "native ps output is malformed; managed process inspection is incomplete",
        )
        if int(values[0]) in managed_uids:
            processes.append(
                {"uid": int(values[0]), "pid": int(values[1]), "command": values[2]}
            )
    return processes


def inspect_local(manifest):
    """Read only native metadata; never dump password hashes or private keys."""
    require(platform.system() == "FreeBSD", "local inspection requires native FreeBSD")

    import grp
    import pwd

    pool = manifest["pool"]["name"]
    guid = run_readonly(
        ["/sbin/zpool", "get", "-H", "-p", "-o", "value", "guid", pool]
    ).strip()
    rows = run_readonly(
        [
            "/sbin/zfs",
            "list",
            "-H",
            "-p",
            "-o",
            "name,mountpoint,mounted,quota",
            "-r",
            pool,
        ]
    )
    datasets = []
    for row in rows.splitlines():
        name, mountpoint, mounted, quota = row.split("\t")
        datasets.append(
            {
                "name": name,
                "mountpoint": mountpoint,
                "mounted": mounted == "yes",
                "quotaBytes": int(quota),
                "metadata": metadata(Path(mountpoint))
                if mountpoint.startswith("/")
                else {"exists": False},
            }
        )
    users = [
        {
            "name": p.pw_name,
            "uid": p.pw_uid,
            "gid": p.pw_gid,
            "home": p.pw_dir,
            "shell": p.pw_shell,
            "groups": sorted(os.getgrouplist(p.pw_name, p.pw_gid)),
            "passwordAuthDisabled": p.pw_passwd.startswith(("*", "!")),
        }
        for p in pwd.getpwall()
    ]
    groups = [
        {"name": g.gr_name, "gid": g.gr_gid, "members": sorted(g.gr_mem)}
        for g in grp.getgrall()
    ]
    files = {}
    for principal in manifest["principals"]:
        home = Path(principal["home"])
        authorized = authorization_path(principal)
        for path in (
            *home.parents,
            home,
            home / ".ssh",
            home / ".ssh/authorized_keys",
            home / ".ssh/authorized_keys2",
            *authorized.parents,
            authorized,
        ):
            files[str(path)] = metadata(path, hash_contents=path == authorized)
        backend = backend_config(principal)
        if backend is not None:
            files[str(backend[0])] = metadata(backend[0], hash_contents=True)
    packages = run_readonly(["/usr/local/sbin/pkg", "query", "%n"]).splitlines()
    files[str(PRIVATE_SSHD_CONFIG)] = metadata(PRIVATE_SSHD_CONFIG, hash_contents=True)
    observed_names = {d["name"] for d in datasets}
    delegation_names = {pool}
    for dataset in manifest["datasets"]:
        parts = dataset["name"].split("/")
        delegation_names.update(
            "/".join(parts[:length])
            for length in range(1, len(parts) + 1)
            if "/".join(parts[:length]) in observed_names
        )
    delegations = {
        name: run_readonly(["/sbin/zfs", "allow", name])
        for name in sorted(delegation_names)
    }
    managed_uids = {
        principal["uid"]
        for principal in manifest["principals"]
        if principal["uid"] is not None
    }
    processes = active_processes(managed_uids)
    repository_entries = {}
    for principal in manifest["principals"]:
        if principal["backend"] != "restic" or principal["dataset"] is None:
            continue
        declared = next(
            d for d in manifest["datasets"] if d["name"] == principal["dataset"]
        )
        path = Path(declared["mountpoint"])
        repository_entries[principal["name"]] = (
            sorted(item.name for item in path.iterdir())
            if path.is_dir() and not path.is_symlink()
            else None
        )
    return {
        "schemaVersion": 1,
        "system": "FreeBSD",
        "pool": {"name": pool, "guid": guid},
        "users": users,
        "groups": groups,
        "datasets": datasets,
        "files": files,
        "packages": sorted(packages),
        "delegations": delegations,
        "activeProcesses": processes,
        "repositoryEntries": repository_entries,
        "sshInspectionContext": "synthetic loopback connection; verify all actual connection contexts before production",
    }


def inspect_remote(
    manifest, *, admin_identity=None, admin_agent_public_key=None, known_hosts=None
):
    return remote_call(
        manifest,
        "_inspect",
        admin_identity=admin_identity,
        admin_agent_public_key=admin_agent_public_key,
        known_hosts=known_hosts,
    )


def ssh_command(manifest, remote, **identity):
    from rsync_net.ssh import command

    return command(manifest, remote, executable=CONFIG.get("ssh", "ssh"), **identity)


def remote_run(manifest, remote, *, input="", timeout=180, progress=False, **identity):
    from rsync_net.ssh import session

    with session(
        manifest,
        executable=CONFIG.get("ssh", "ssh"),
        fail_executable=CONFIG.get("sshFail"),
        **identity,
    ) as connection:
        return connection.run(remote, input=input, timeout=timeout, progress=progress)


def remote_call(
    manifest,
    operation,
    *,
    admin_identity=None,
    admin_agent_public_key=None,
    known_hosts=None,
    review_digest=None,
    payload=None,
):
    connection = manifest["connection"]
    source = Path(__file__).read_text()
    helpers = {}
    for kind in ("apply", "control", "setup", "storage", "snapshots"):
        helpers[kind] = Path(__file__).with_name(kind + ".py").read_text()
    helpers["sshdPolicy"] = asset("sshdPolicy")
    helpers["sshdTemplate"] = asset("sshdTemplate")
    # A small, one-line csh-compatible launcher reads the trusted helper/policy
    # envelope over administrative SSH; private identities never enter stdin.
    code = 'import json,sys;p=json.load(sys.stdin);sys.argv=["rsync-net",p["operation"]];globals().update(__file__="/root/rsync_net/cli.py",REMOTE_MANIFEST=p["manifest"],REMOTE_HELPERS=p["helpers"],REMOTE_REVIEW_DIGEST=p["reviewDigest"],REMOTE_PAYLOAD=p["payload"]);exec(compile(p["source"],"rsync_net/cli.py","exec"));raise SystemExit(main())'
    remote = connection["interpreter"] + " -c " + shlex.quote(code)
    result = remote_run(
        manifest,
        remote,
        admin_identity=admin_identity,
        admin_agent_public_key=admin_agent_public_key,
        known_hosts=known_hosts,
        input=json.dumps(
            {
                "manifest": manifest,
                "operation": operation,
                "source": source,
                "helpers": helpers,
                "reviewDigest": review_digest,
                "payload": payload,
            }
        ),
        timeout=1800 if operation == "_setup" else 180,
        progress=True,
    )
    if result.returncode and not (
        operation in {"_setup-review", "_storage-review", "_snapshots-review"}
        and result.returncode == 1
    ):
        detail = next(
            (
                line[:400]
                for line in result.stderr.splitlines()
                if line.startswith("rsync-net: ")
                and not line.startswith("rsync-net: phase ")
            ),
            "",
        )
        consequence = (
            "no changes were requested"
            if operation
            in {
                "_inspect",
                "_setup-review",
                "_storage-review",
                "_snapshots-review",
                "_control-review",
                "_control-fetch",
            }
            else "partial reconstruction/publication may remain; inspect before retry"
        )
        raise PolicyError(
            f"remote controller failed (exit {result.returncode}); {consequence}. {detail}"
        )
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise PolicyError("remote inspector did not return valid JSON") from error


def plan(manifest, state):
    require(
        state.get("schemaVersion") == 1 and state.get("system") == "FreeBSD",
        "state must be a version-1 native FreeBSD inspection",
    )
    blockers, actions = [], []
    if manifest["mode"] == "private":
        blockers.append("private mode is incomplete; activation is disabled")
    if manifest["pool"]["guid"] is None:
        blockers.append("expected pool GUID is not approved")
    if state.get("pool") != manifest["pool"]:
        blockers.append("pool name or GUID differs from expected storage")
    users = state.get("users", [])
    groups = state.get("groups", [])
    observed_datasets = {d["name"]: d for d in state.get("datasets", [])}
    for principal in manifest["principals"]:
        name, uid, gid = (principal[k] for k in ("name", "uid", "gid"))
        if uid is None or gid is None:
            blockers.append(f"{name}: UID/GID allocation is not approved")
            continue
        same_name = [u for u in users if u["name"] == name]
        if not same_name and any(
            process["uid"] == uid for process in state.get("activeProcesses", [])
        ):
            blockers.append(
                f"{name}: reserved UID still has live processes without its declared account"
            )
        if any(u["uid"] == uid and u["name"] != name for u in users):
            blockers.append(f"{name}: reserved UID belongs to another account")
        if any(g["gid"] == gid and g["name"] != name for g in groups):
            blockers.append(f"{name}: reserved GID belongs to another group")
        if any(g["name"] == name and g["gid"] != gid for g in groups):
            blockers.append(f"{name}: named group has a different GID")
        if any(
            g["name"] == name and set(g.get("members", [])) - {name} for g in groups
        ):
            blockers.append(f"{name}: principal group contains unrelated members")
        if same_name:
            user = same_name[0]
            if user.get("passwordAuthDisabled") is not True:
                blockers.append(
                    f"{name}: password authentication is not proved disabled; public fallback is unsafe"
                )
            if (user["uid"], user["gid"], user["home"], user["shell"]) != (
                uid,
                gid,
                principal["home"],
                "/bin/sh",
            ) or set(user.get("groups", [])) != {gid}:
                blockers.append(
                    f"{name}: existing identity/home/shell/group membership differs; never renumber or silently alter it"
                )
        else:
            actions.append(
                {
                    "kind": "create-user",
                    "argv": [
                        "/usr/sbin/pw",
                        "useradd",
                        name,
                        "-u",
                        str(uid),
                        "-g",
                        str(gid),
                        "-d",
                        principal["home"],
                        "-s",
                        "/bin/sh",
                        "-w",
                        "no",
                    ],
                    "stage": "after package installation and account reinspection",
                }
            )
        if not any(g["name"] == name and g["gid"] == gid for g in groups):
            actions.insert(
                0,
                {
                    "kind": "create-group",
                    "argv": ["/usr/sbin/pw", "groupadd", name, "-g", str(gid)],
                },
            )
        if not principal["publicKeys"]:
            blockers.append(f"{name}: no approved public device keys")
        if principal["dataset"] is None:
            blockers.append(f"{name}: no approved repository dataset")
        if principal["publicKeys"] and principal["dataset"] is not None:
            backend = backend_config(principal)
            if backend is not None:
                backend_path, backend_content = backend
                info = state.get("files", {}).get(str(backend_path))
                if info is None:
                    blockers.append(f"{name}: backend configuration was not inspected")
                elif info.get("exists") and (
                    info.get("symlink")
                    or info.get("uid") != 0
                    or info.get("mode", 0) & 0o022
                ):
                    blockers.append(
                        f"{name}: backend configuration is not root-controlled"
                    )
                elif not info.get("exists") or (
                    info.get("mode") != 0o644
                    or info.get("sha256")
                    != hashlib.sha256(backend_content.encode()).hexdigest()
                ):
                    actions.append(
                        {
                            "kind": "restore-backend-config",
                            "path": str(backend_path),
                            "owner": "root",
                            "group": "wheel",
                            "mode": "0644",
                            "publicContent": backend_content,
                        }
                    )
            desired = authorization(manifest, principal)
            public_path = principal["home"] + "/.ssh/authorized_keys2"
            info = state.get("files", {}).get(public_path)
            if info is None or info.get("exists"):
                blockers.append(
                    f"{name}: undeclared public SSH key path is present or uninspected: {public_path}"
                )
            path = str(authorization_path(principal))
            observed = state.get("files", {}).get(path, {"exists": False})
            authority = Path(path)
            for control in [str(item) for item in reversed(authority.parents)] + [path]:
                info = state.get("files", {}).get(control)
                if info is None:
                    blockers.append(
                        f"{name}: enforcement ancestor {control} was not inspected"
                    )
                    continue
                if not info["exists"] and control == "/":
                    blockers.append(f"{name}: inspected root directory is absent")
                elif not info["exists"] and control != path:
                    actions.append(
                        {
                            "kind": "restore-control-directory",
                            "path": control,
                            "owner": "root",
                            "group": "wheel",
                            "mode": "0755",
                        }
                    )
                if info["exists"] and (
                    info.get("symlink")
                    or info.get("uid") != 0
                    or info.get("mode", 0) & 0o022
                ):
                    blockers.append(
                        f"{name}: client-writable, non-root-owned or symlinked enforcement path {control}"
                    )
                if (
                    info["exists"]
                    and control in {principal["home"], str(authority.parent)}
                    and info.get("mode") != 0o755
                ):
                    actions.append(
                        {
                            "kind": "restore-control-directory",
                            "path": control,
                            "owner": "root",
                            "group": "wheel",
                            "mode": "0755",
                        }
                    )
                elif (
                    info["exists"]
                    and control != path
                    and control not in {principal["home"], str(authority.parent)}
                    and not info.get("mode", 0) & 0o001
                ):
                    blockers.append(
                        f"{name}: public authorization ancestor is not searchable after UID drop: {control}"
                    )
            if (
                observed.get("sha256") != hashlib.sha256(desired.encode()).hexdigest()
                or observed.get("mode") != 0o644
            ):
                actions.append(
                    {
                        "kind": "restore-authorization",
                        "path": path,
                        "owner": "root",
                        "group": "wheel",
                        "mode": "0644",
                        "sha256": hashlib.sha256(desired.encode()).hexdigest(),
                        "publicContent": desired,
                    }
                )
    for dataset in manifest["datasets"]:
        name = dataset["name"]
        actual = observed_datasets.get(name)
        if actual is None:
            blockers.append(f"{name}: dataset absent; recovery never creates storage")
            continue
        owner = next(
            p for p in manifest["principals"] if p["name"] == dataset["principal"]
        )
        metadata_ = actual.get("metadata", {})
        if (
            actual.get("mountpoint") != dataset["mountpoint"]
            or not actual.get("mounted")
            or not metadata_.get("exists")
            or metadata_.get("symlink")
        ):
            blockers.append(f"{name}: expected dataset is not mounted safely")
        if metadata_.get("uid") != owner["uid"] or metadata_.get("gid") != owner["gid"]:
            blockers.append(
                f"{name}: numeric ownership differs; recovery never recursively chowns data"
            )
        if metadata_.get("mode", 0) & 0o007:
            blockers.append(f"{name}: repository mountpoint grants other users access")
        if dataset["quotaBytes"] is None:
            blockers.append(f"{name}: quota allocation is not approved")
        elif actual.get("quotaBytes") != dataset["quotaBytes"]:
            blockers.append(
                f"{name}: quota differs; storage policy changes require separate review"
            )
    caches = [p for p in manifest["principals"] if p["backend"] == "nix-cache"]
    for principal in caches:
        if not principal["cache"]["signingPublicKeys"]:
            blockers.append(
                f"{principal['name']}: no approved public signing keys; signing secrets must remain off server"
            )
    if manifest["control"]["enable"] and manifest["control"]["path"] is None:
        blockers.append("control: durable directory is not approved")
    needed = set()
    for principal in manifest["principals"]:
        needed.update(
            {"restic": {"rclone"}, "git": {"rsync"}, "nix-cache": {"nix"}}[
                principal["backend"]
            ]
        )
    for package in sorted(needed - set(state.get("packages", []))):
        actions.append(
            {
                "kind": "install-package",
                "argv": ["/usr/sbin/pkg", "install", package],
                "requires": "provider-approved supported package repository; recheck all accounts afterward",
            }
        )
    if manifest["principals"] and manifest["mode"] == "private":
        content = private_sshd_config(manifest)
        if (
            state.get("files", {}).get(str(PRIVATE_SSHD_CONFIG), {}).get("sha256")
            != hashlib.sha256(content.encode()).hexdigest()
            or state.get("files", {}).get(str(PRIVATE_SSHD_CONFIG), {}).get("mode")
            != 0o600
        ):
            actions.append(
                {
                    "kind": "restore-private-sshd-config",
                    "path": str(PRIVATE_SSHD_CONFIG),
                    "owner": "root",
                    "mode": "0600",
                    "publicContent": content,
                    "activation": "separate provider-compatible service/Tailscale verification; no activation by reconstruction",
                }
            )
    return {
        "schemaVersion": 1,
        "applySupported": manifest["mode"] == "public",
        "applyScope": "declared identities and root-managed public SSH forced-command authorization; no service/package/storage operations",
        "deploymentReady": False,
        "recovery": {
            "policyOnly": True,
            "provisioningVerified": False,
            "principals": [
                {"name": p["name"], **p["recovery"]}
                for p in manifest["principals"]
                if p["backend"] in {"restic", "git"}
            ],
            "requiredSetup": "Provision and independently test each repository's recovery access, with explicit recovery-material storage locations. Account bootstrap does not create or inspect recovery secrets.",
        },
        "blockers": sorted(set(blockers)),
        "actions": actions,
        "requiredVerification": [
            "quiesce and contain managed access including established sessions",
            "inspect all managed dataset delegations and inherited ACLs",
            "verify forced-command executables and every parent path are root-owned and client-unwritable",
            "verify running SSH per-user effective restrictions and all authorized-key paths",
            "verify provider public SSH accepts only declared root-managed forced-command keys; no CA/key-command/alternate authentication sources",
            "native protocol isolation/deletion tests and independent restore",
            "verify native SSH cache signatures/read-only access and snapshot scheduling",
            "verify rrsync availability/provenance; installing rsync alone does not prove that the helper is installed",
        ],
        "note": "Read-only plan only. No actions execute. Even an empty blockers list is not production authorization or proof of safety.",
    }


def recovery_command(args, manifest):
    """Orchestrate native local crypto and bounded administrative publication."""
    local = load_helper("recovery")

    def principal(name):
        selected = next((p for p in manifest["principals"] if p["name"] == name), None)
        require(selected is not None, "undeclared recovery principal")
        return selected

    if args.command == "recovery":
        options = {
            "repository": args.repository,
            "restic": globals().get("CONFIG", {}).get("restic", "restic"),
            "gpg": globals().get("CONFIG", {}).get("gpg", "gpg"),
            "gnupghome": args.gnupghome,
            "restic_options": tuple(
                item for value in args.restic_option for item in ("-o", value)
            ),
        }
        if args.recovery_command == "prepare":
            return local.prepare(
                principal(args.principal),
                password_file=args.password_file,
                password_command=args.password_command,
                output=args.output,
                signing_key=args.signing_key,
                **options,
            )
        return local.restore(
            principal(args.principal),
            bundle=args.bundle,
            target=args.target,
            snapshot=args.snapshot,
            **options,
        )

    administrative = {
        "admin_identity": args.admin_identity,
        "admin_agent_public_key": args.admin_agent_public_key,
        "known_hosts": args.known_hosts,
    }
    if args.control_command == "fetch":
        require(
            args.catalog or args.output is not None, "bundle fetch requires --output"
        )
        require(
            not args.catalog or args.output is None,
            "catalog fetch writes public JSON to stdout",
        )
        result = remote_call(
            manifest,
            "_control-fetch",
            payload={"principal": args.principal},
            **administrative,
        )
        if args.catalog:
            return result
        return local.save_bundle(
            principal(args.principal),
            output=args.output,
            metadata=result["metadata"],
            encrypted_password=result["encryptedPassword"],
        )

    require(
        (args.bundle is None) == (args.principal is None),
        "supply --principal and --bundle together, or omit both for catalog-only backup",
    )
    payload = None
    if args.bundle is not None:
        bundle = local.read_bundle(principal(args.principal), args.bundle)
        payload = {
            key: bundle["metadata"][key]
            for key in ("principal", "repositoryId", "keyId", "recipients")
        }
        payload["encryptedPassword"] = bundle["encryptedPassword"]
    require(args.apply or args.review is None, "--review is only used with --apply")
    if not args.apply:
        return remote_call(
            manifest, "_control-review", payload=payload, **administrative
        )
    require(args.review is not None, "control publication requires a saved --review")
    review = json.loads(args.review.read_text())
    digest = review.get("reviewDigest")
    require(
        isinstance(digest, str) and re.fullmatch(r"[a-f0-9]{64}", digest),
        "invalid control review digest",
    )
    return remote_call(
        manifest,
        "_control-publish",
        payload=payload,
        review_digest=digest,
        **administrative,
    )


def _main():
    parser = argparse.ArgumentParser(prog="rsync-net", description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path(CONFIG["manifest"]) if CONFIG.get("manifest") else None,
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("validate")
    git_command = commands.add_parser(
        "git", help="set up per-machine encrypted Git credentials"
    )
    git_commands = git_command.add_subparsers(dest="git_command", required=True)
    git_commands.add_parser("setup").add_argument("--config", type=Path, required=True)
    inspector = commands.add_parser("inspect")
    inspector.add_argument("--local", action="store_true")

    def administrative_options(command, *, required=False):
        identity = command.add_mutually_exclusive_group(required=required)
        identity.add_argument(
            "--admin-identity",
            type=Path,
            help="explicit administrative private key; SSH agent disabled",
        )
        identity.add_argument(
            "--admin-agent-public-key",
            type=Path,
            help="explicit public selector for a key held by the administrative SSH agent",
        )
        command.add_argument(
            "--known-hosts",
            type=Path,
            help="existing trusted host-key file; no automatic key acceptance",
        )

    administrative_options(inspector)
    planner = commands.add_parser("plan")
    planner.add_argument("--state", required=True, type=Path)
    enrollment = commands.add_parser(
        "enroll",
        help="create/verify a local device key and emit public Nix enrollment policy",
        description="Enroll a device in a shared principal, inheriting declared recovery policy. Public policy does not provision repository encryption or recovery secrets.",
    )
    enrollment.add_argument("--principal", required=True)
    enrollment.add_argument("--device", required=True)
    key = enrollment.add_mutually_exclusive_group(required=True)
    key.add_argument(
        "--key-file",
        type=Path,
        help="source-local private key path, outside Git/Nix store; never uploaded",
    )
    key.add_argument(
        "--public-key",
        type=Path,
        help="public key from a different source machine; private key stays there",
    )
    enrollment.add_argument(
        "--gpg-fingerprint",
        help="full public OpenPGP fingerprint for Git decryption membership, not per-device write permission",
    )
    enrollment.add_argument(
        "--read-only",
        action="store_true",
        help="enroll a Git or Nix cache reader; Restic retains append-only access",
    )
    enrollment.add_argument("--output", required=True, type=Path)
    enrollment.add_argument(
        "--new-account",
        action="store_true",
        help="declare an account with explicit IDs and existing storage; does not create it remotely",
    )
    enrollment.add_argument(
        "--backend",
        choices=sorted(BACKENDS),
        help="storage backend shared by device keys; Git writers must serialize updates",
    )
    enrollment.add_argument(
        "--uid", type=int, help="reserved stable nonroot UID; never auto-allocated"
    )
    enrollment.add_argument(
        "--gid", type=int, help="reserved stable primary GID; never auto-allocated"
    )
    enrollment.add_argument(
        "--dataset", help="existing ZFS dataset; enrollment never creates storage"
    )
    enrollment.add_argument("--dataset-label")
    enrollment.add_argument(
        "--quota-bytes", type=int, help="explicit snapshot-inclusive dataset quota"
    )
    enrollment.add_argument("--purpose", choices=["user", "service", "git", "cache"])
    setup_command = commands.add_parser(
        "setup", help="review server prerequisites; per-backup accounts use bootstrap"
    )
    administrative_options(setup_command, required=True)
    setup_command.add_argument("--apply", action="store_true")
    setup_command.add_argument("--review", type=Path)
    storage = commands.add_parser(
        "storage", help="review and provision declared ZFS filesystems"
    )
    storage_commands = storage.add_subparsers(dest="storage_command", required=True)
    storage_init = storage_commands.add_parser("init")
    administrative_options(storage_init, required=True)
    selection = storage_init.add_mutually_exclusive_group(required=True)
    selection.add_argument("--principal")
    selection.add_argument("--control", action="store_true")
    storage_init.add_argument("--apply", action="store_true")
    storage_init.add_argument("--review", type=Path)
    backup = commands.add_parser(
        "backup", help="set up a declarative backup with required recovery escrow"
    )
    backup_commands = backup.add_subparsers(dest="backup_command", required=True)
    backup_setup = backup_commands.add_parser("setup")
    administrative_options(backup_setup, required=True)
    backup_setup.add_argument("--config", type=Path, required=True)
    backup_setup.add_argument("--signing-key")
    backup_setup.add_argument("--review", type=Path)
    backup_setup.add_argument("--apply", action="store_true")
    snapshots = commands.add_parser(
        "snapshots", help="manage declarative server-side ZFS snapshot schedules"
    )
    snapshot_commands = snapshots.add_subparsers(
        dest="snapshots_command", required=True
    )
    snapshot_configure = snapshot_commands.add_parser("configure")
    administrative_options(snapshot_configure, required=True)
    snapshot_configure.add_argument("--review", type=Path)
    snapshot_configure.add_argument("--apply", action="store_true")
    bootstrapper = commands.add_parser(
        "bootstrap",
        help="inspect over explicit administrative SSH and produce a recovery review",
    )
    administrative_options(bootstrapper, required=True)
    bootstrapper.add_argument(
        "--principal",
        help="review/apply only this declared principal; unrelated active clients remain outside the scope",
    )
    bootstrapper.add_argument(
        "--apply",
        action="store_true",
        help="reconstruct declared identities/public home SSH authorization from a saved fresh review; no service activation",
    )
    bootstrapper.add_argument(
        "--review",
        type=Path,
        help="saved bootstrap review required for freshly matched bounded reconstruction",
    )
    recovery = commands.add_parser(
        "recovery", help="prepare or use a Restic recovery bundle"
    )
    recovery_commands = recovery.add_subparsers(dest="recovery_command", required=True)
    for action in ("prepare", "restore"):
        command = recovery_commands.add_parser(action)
        command.add_argument("--principal", required=True)
        command.add_argument("--repository", required=True)
        command.add_argument("--gnupghome", type=Path)
        command.add_argument("--restic-option", action="append", default=[])
        if action == "prepare":
            password = command.add_mutually_exclusive_group(required=True)
            password.add_argument("--password-file", type=Path)
            password.add_argument(
                "--password-command",
                help="credential-provider command passed to Restic; never include the password itself",
            )
            command.add_argument("--output", required=True, type=Path)
            command.add_argument("--signing-key")
        else:
            command.add_argument("--bundle", required=True, type=Path)
            command.add_argument("--target", required=True, type=Path)
            command.add_argument("--snapshot", default="latest")
    control = commands.add_parser(
        "control", help="review, back up or fetch administrative control data"
    )
    control_commands = control.add_subparsers(dest="control_command", required=True)
    backup = control_commands.add_parser("backup")
    administrative_options(backup, required=True)
    backup.add_argument("--principal")
    backup.add_argument("--bundle", type=Path)
    backup.add_argument("--review", type=Path)
    backup.add_argument("--apply", action="store_true")
    fetch = control_commands.add_parser("fetch")
    administrative_options(fetch, required=True)
    selection = fetch.add_mutually_exclusive_group(required=True)
    selection.add_argument("--principal")
    selection.add_argument("--catalog", action="store_true")
    fetch.add_argument("--output", type=Path)
    commands.add_parser("apply")
    for operation in (
        "_inspect",
        "_setup",
        "_setup-review",
        "_storage-review",
        "_storage-init",
        "_snapshots-review",
        "_snapshots-configure",
        "_reconstruct",
        "_control-review",
        "_control-publish",
        "_control-fetch",
    ):
        commands.add_parser(operation, help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        if args.command == "apply":
            raise PolicyError("apply is not implemented; no remote state was changed")
        if args.command in {
            "_inspect",
            "_setup",
            "_setup-review",
            "_storage-review",
            "_storage-init",
            "_snapshots-review",
            "_snapshots-configure",
            "_reconstruct",
            "_control-review",
            "_control-publish",
            "_control-fetch",
        }:
            manifest = validate(
                globals().get("REMOTE_MANIFEST") or json.load(sys.stdin)
            )
            if args.command in {"_setup", "_reconstruct", "_control-publish"}:
                require(
                    manifest["mode"] == "public",
                    "private mode is incomplete; activation is disabled",
                )
            if args.command == "_setup-review":
                controller = load_helper("setup")
                result = controller.review_remote(
                    manifest,
                    transport=(globals().get("REMOTE_PAYLOAD") or {}).get("transport"),
                )
            elif args.command == "_setup":
                controller = load_helper("setup")
                result = controller.configure_remote(
                    manifest,
                    load_helper=load_helper,
                    config_path=PRIVATE_SSHD_CONFIG,
                    reviewed=(globals().get("REMOTE_PAYLOAD") or {}).get("review"),
                    expected_digest=globals().get("REMOTE_REVIEW_DIGEST"),
                    transport=(globals().get("REMOTE_PAYLOAD") or {}).get("transport"),
                    prerequisites_prepared=(globals().get("REMOTE_PAYLOAD") or {}).get(
                        "prerequisitesPrepared", False
                    ),
                )
            elif args.command in {"_storage-review", "_storage-init"}:
                controller = load_helper("storage")
                result = controller.remote(
                    manifest,
                    payload=globals().get("REMOTE_PAYLOAD"),
                    apply=args.command == "_storage-init",
                    expected_digest=globals().get("REMOTE_REVIEW_DIGEST"),
                    inspect=inspect_local,
                    engine=load_helper("apply"),
                )
            elif args.command in {"_snapshots-review", "_snapshots-configure"}:
                result = load_helper("snapshots").remote(
                    manifest,
                    payload=globals().get("REMOTE_PAYLOAD"),
                    apply=args.command == "_snapshots-configure",
                    expected_digest=globals().get("REMOTE_REVIEW_DIGEST"),
                    inspect=inspect_local,
                    engine=load_helper("apply"),
                )
            elif args.command != "_inspect":
                engine = load_helper("apply")
                backend = engine.FreeBSD()
                try:
                    if args.command == "_reconstruct":
                        result = engine.reconstruct(
                            manifest,
                            backend=backend,
                            inspect=inspect_local,
                            plan=plan,
                            digest=plan_digest,
                            expected_digest=globals().get("REMOTE_REVIEW_DIGEST"),
                            authorization=authorization,
                            legacy_authorization=legacy_authorization,
                            backend_config=backend_config,
                            authorization_path=authorization_path,
                            config_path=PRIVATE_SSHD_CONFIG,
                            config_content=private_sshd_config(manifest)
                            if manifest["mode"] == "private"
                            else "",
                        )
                    else:
                        controller = load_helper("control")
                        context = {
                            "validate": validate,
                            "inspect": inspect_local,
                            "engine": engine,
                            "backend": backend,
                        }
                        payload = globals().get("REMOTE_PAYLOAD")
                        if args.command == "_control-review":
                            result = controller.review(manifest, payload, **context)
                        elif args.command == "_control-publish":
                            result = controller.publish(
                                manifest,
                                payload,
                                expected_digest=globals().get("REMOTE_REVIEW_DIGEST"),
                                **context,
                            )
                        else:
                            require(
                                isinstance(payload, dict),
                                "invalid control fetch request",
                            )
                            result = controller.fetch(
                                manifest, payload.get("principal"), **context
                            )
                except ValueError as error:
                    raise PolicyError(str(error)) from error
            else:
                result = inspect_local(manifest)
        else:
            require(
                args.manifest is not None,
                "--manifest is required outside the generated Nix package",
            )
            manifest = validate(json.loads(args.manifest.read_text()))
            if args.command == "validate":
                result = {
                    "schemaVersion": 1,
                    "valid": True,
                    "principals": len(manifest["principals"]),
                    "datasets": len(manifest["datasets"]),
                    "privateCaches": [
                        p["name"]
                        for p in manifest["principals"]
                        if p["backend"] == "nix-cache"
                    ],
                    "applySupported": manifest["mode"] == "public",
                }
            elif args.command == "git":
                result = load_helper("git").setup(
                    args.config, manifest, gpg=CONFIG.get("gpg", "gpg")
                )
            elif args.command == "setup":
                controller = load_helper("setup")
                result = controller.setup(
                    args,
                    manifest,
                    remote_run=remote_run,
                    remote_call=remote_call,
                )
            elif args.command == "storage":
                result = load_helper("storage").initialize(
                    args,
                    manifest,
                    remote_call=remote_call,
                    transport=load_helper("setup").transport_policy(args),
                )
            elif args.command == "backup":
                result = load_helper("backup").setup(
                    args,
                    manifest,
                    load_helper=load_helper,
                    remote_call=remote_call,
                    validate=validate,
                    plan=plan,
                    transport=load_helper("setup").transport_policy(args),
                    restic=CONFIG.get("restic", "restic"),
                    gpg=CONFIG.get("gpg", "gpg"),
                )
            elif args.command == "snapshots":
                result = load_helper("snapshots").configure(
                    args,
                    manifest,
                    remote_call=remote_call,
                    transport=load_helper("setup").transport_policy(args),
                )
            elif args.command in {"recovery", "control"}:
                try:
                    result = recovery_command(args, manifest)
                except ValueError as error:
                    raise PolicyError(str(error)) from error
            elif args.command == "inspect":
                result = (
                    inspect_local(manifest)
                    if args.local
                    else inspect_remote(
                        manifest,
                        admin_identity=args.admin_identity,
                        admin_agent_public_key=args.admin_agent_public_key,
                        known_hosts=args.known_hosts,
                    )
                )
            elif args.command in {"enroll", "bootstrap"}:
                controller = load_helper("enrollment")
                try:
                    if args.command == "enroll":
                        result = controller.enroll(
                            args,
                            manifest,
                            validate=validate,
                            keygen=globals()
                            .get("CONFIG", {})
                            .get("sshKeygen", "ssh-keygen"),
                        )
                    else:
                        result = controller.bootstrap(
                            args,
                            scoped_principal(manifest, args.principal)
                            if args.principal is not None
                            else manifest,
                            inspect_remote=inspect_remote,
                            plan=plan,
                            digest=plan_digest,
                            reconstruct_remote=lambda policy, **options: remote_call(
                                policy, "_reconstruct", **options
                            ),
                        )
                except controller.EnrollmentError as error:
                    raise PolicyError(str(error)) from error
            else:
                result = plan(manifest, json.loads(args.state.read_text()))
        print(json.dumps(result, indent=2, sort_keys=True))
        return 1 if result.get("blockers") else 0
    except (
        PolicyError,
        OSError,
        json.JSONDecodeError,
        subprocess.TimeoutExpired,
        ValueError,
    ) as error:
        print(f"rsync-net: {error}", file=sys.stderr)
        return 2


def main():
    if "REMOTE_MANIFEST" in globals():
        return _main()
    from rsync_net.ssh import invocation

    with invocation():
        return _main()
