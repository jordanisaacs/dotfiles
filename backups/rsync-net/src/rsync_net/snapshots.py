"""Reviewed FreeBSD cron scheduling using native zfsnap2 and scoped TTL expiry."""

import hashlib
import json
import shlex
import stat
import subprocess
from pathlib import Path

CRON = Path("/etc/cron.d/rsync-net-snapshots")
TOOL = Path("/usr/local/sbin/zfsnap")
HEADER = "# Managed by rsync-net; dataset snapshot schedules.\n"
PREFIX = "rsync-net-"


class SnapshotError(ValueError):
    """Unsafe, stale or incomplete snapshot schedule configuration."""


def require(condition, message):
    if not condition:
        raise SnapshotError(message)


def digest(value):
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def jobs(manifest):
    result = []
    for dataset in sorted(manifest["datasets"], key=lambda d: d["name"]):
        for label, policy in sorted(dataset.get("snapshots", {}).items()):
            arguments = [
                str(TOOL),
                "snapshot",
                "-z",
                "-p",
                PREFIX + label + "-",
                "-a",
                policy["retention"],
                "-R",
                dataset["name"],
            ]
            result.append(
                {
                    "dataset": dataset["name"],
                    "label": label,
                    "schedule": policy["schedule"],
                    "retention": policy["retention"],
                    "arguments": arguments,
                }
            )
        if dataset.get("snapshots"):
            # zfsnap matches the *entire* parsed prefix, not a starts-with
            # pattern. Each declared tier must be listed explicitly.
            prefixes = [
                argument
                for label in sorted(dataset["snapshots"])
                for argument in ("-p", PREFIX + label + "-")
            ]
            result.append(
                {
                    "dataset": dataset["name"],
                    "label": "cleanup",
                    "schedule": "55 * * * *",
                    "retention": None,
                    "arguments": [
                        str(TOOL),
                        "destroy",
                        *prefixes,
                        "-R",
                        dataset["name"],
                    ],
                }
            )
    return result


def render(manifest):
    lines = [
        HEADER.rstrip(),
        "PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin",
        'MAILTO=""',
    ]
    for job in jobs(manifest):
        token = hashlib.sha256(job["dataset"].encode()).hexdigest()[:16]
        command = shlex.join(
            [
                "/usr/bin/lockf",
                "-k",
                "-t",
                "0",
                "/var/run/rsync-net-snapshots-" + token + ".lock",
                *job["arguments"],
            ]
        )
        lines.append(
            job["schedule"]
            + " root "
            + command
            + " 2>&1 | /usr/bin/logger -t rsync-net-snapshots"
        )
    return "\n".join(lines) + "\n"


def review(manifest, state, *, transport):
    content = render(manifest)
    blockers = []
    active = [d for d in manifest["datasets"] if d.get("snapshots")]
    if manifest["mode"] != "public":
        blockers.append("private mode is incomplete")
    if not manifest["pool"]["guid"] or state["pool"] != manifest["pool"]:
        blockers.append("pool identity differs from the approved pool")
    if not state["cronRunning"]:
        blockers.append("provider cron is not running")
    if active and (not manifest["setup"]["snapshotting"] or not state["toolVersion"]):
        blockers.append(
            "run reviewed server setup with setup.snapshotting enabled to install zfsnap2"
        )
    if state["before"]["exists"] and not state["before"]["managed"]:
        blockers.append(
            "existing snapshot cron file is unmanaged; it will not be overwritten"
        )
    observed = {d["name"]: d for d in state["datasets"]}
    for dataset in active:
        actual = observed.get(dataset["name"])
        owner = next(
            p for p in manifest["principals"] if p["name"] == dataset["principal"]
        )
        if actual is None:
            blockers.append(dataset["name"] + ": dataset is missing")
            continue
        info = actual["metadata"]
        if (
            not actual["mounted"]
            or actual["mountpoint"] != dataset["mountpoint"]
            or [dataset["name"], dataset["mountpoint"], "zfs"] not in state["mounts"]
            or not info.get("exists")
            or info.get("symlink")
            or (info.get("uid"), info.get("gid")) != (owner["uid"], owner["gid"])
            or info.get("mode", 0) & 0o007
            or actual["quotaBytes"] != dataset["quotaBytes"]
        ):
            blockers.append(
                dataset["name"]
                + ": mounted storage/ownership/quota differs from policy"
            )
        parts = dataset["name"].split("/")
        if any(
            state["delegations"].get("/".join(parts[:n]), "").strip()
            for n in range(1, len(parts) + 1)
        ):
            blockers.append(
                dataset["name"]
                + ": delegated ZFS access would undermine snapshot isolation"
            )
    result = {
        "operation": "snapshot-schedule-review",
        "schemaVersion": 1,
        "cronFile": str(CRON),
        "content": content,
        "jobs": jobs(manifest),
        "transport": transport,
        "state": state,
        "changed": (
            state["before"]["sha256"] != hashlib.sha256(content.encode()).hexdigest()
            or state["before"].get("mode") != 0o644
        ),
        "blockers": sorted(set(blockers)),
        "scope": "Only declared datasets, non-recursive snapshots, and expiry of rsync-net-prefixed snapshots",
    }
    result["reviewDigest"] = digest({"manifest": manifest, "review": result})
    return result


def observe(manifest, *, inspect, engine, backend):
    inspected = inspect(manifest)
    engine.protected(CRON)
    for ancestor in (*CRON.parents, CRON):
        if ancestor.exists():
            backend.check_acl(ancestor)
    before = {"exists": CRON.exists(), "sha256": None, "managed": True, "mode": None}
    if CRON.exists():
        info = CRON.lstat()
        require(
            stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
            "snapshot cron file must be a single-link regular file",
        )
        require(info.st_size <= 1048576, "snapshot cron file exceeds its size bound")
        content = CRON.read_text()
        before.update(
            sha256=hashlib.sha256(content.encode()).hexdigest(),
            managed=content.startswith(HEADER),
            mode=stat.S_IMODE(info.st_mode),
        )
    active_names = {d["name"] for d in manifest["datasets"] if d.get("snapshots")}
    tool_version = None
    executables = [Path("/sbin/zfs"), Path("/usr/bin/lockf"), Path("/usr/bin/logger")]
    if active_names and TOOL.exists():
        executables += [TOOL]
        tool_version = engine.native([str(TOOL), "-V"]).strip()
        require("2." in tool_version, "snapshot schedules require native zfsnap2")
        engine.protected(Path("/usr/local/share/zfsnap"), directory=True)
    for path in executables:
        engine.protected(path)
        for ancestor in (*path.parents, path):
            if ancestor.exists():
                backend.check_acl(ancestor)
    for dataset in manifest["datasets"]:
        if dataset["name"] in active_names:
            engine.protected(Path(dataset["mountpoint"]).parent, directory=True)
            backend.check_acl(Path(dataset["mountpoint"]))
    status = subprocess.run(
        ["/usr/sbin/service", "cron", "onestatus"],
        input="",
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    return {
        "pool": inspected["pool"],
        "datasets": [d for d in inspected["datasets"] if d["name"] in active_names],
        "delegations": inspected["delegations"],
        "mounts": [
            line.split()[:3]
            for line in engine.native(["/sbin/mount", "-p"]).splitlines()
        ],
        "toolVersion": tool_version,
        "cronRunning": status.returncode == 0,
        "before": before,
    }


def remote(manifest, *, payload, apply, expected_digest, inspect, engine):
    backend = engine.FreeBSD()
    backend.check()
    require(
        isinstance(payload, dict) and set(payload) == {"transport"},
        "invalid snapshot configuration request",
    )
    with engine.reconstruction_lock():
        state = observe(manifest, inspect=inspect, engine=engine, backend=backend)
        current = review(manifest, state, transport=payload["transport"])
        if not current["blockers"]:
            # Exercise the native snapshot/expiry parsers without creating or
            # deleting anything. Actual expiry runs only from the installed cron.
            for job in current["jobs"]:
                arguments = job["arguments"]
                engine.native([*arguments[:2], "-n", *arguments[2:]])
        if not apply:
            return current
        require(
            current["reviewDigest"] == expected_digest,
            "snapshot review is stale or belongs to different policy/trust",
        )
        require(not current["blockers"], "snapshot review contains blockers")
        changed = engine.atomic_file(CRON, current["content"], mode=0o644)
        require(
            CRON.read_text() == current["content"]
            and stat.S_IMODE(CRON.stat().st_mode) == 0o644,
            "snapshot cron readback differs from the reviewed schedule",
        )
        return {
            "operation": "snapshot-schedule-configuration",
            "schemaVersion": 1,
            "cronFile": str(CRON),
            "changed": changed,
            "jobs": current["jobs"],
            "verifiedSha256": hashlib.sha256(current["content"].encode()).hexdigest(),
            "snapshotsCreated": False,
            "snapshotsDeleted": False,
            "cronReload": "automatic native cron reload; provider jobs are unchanged",
        }


def configure(args, manifest, *, remote_call, transport):
    require(args.apply or args.review is None, "--review is only used with --apply")
    require(
        not args.apply or args.review is not None,
        "snapshots configure --apply requires a saved --review",
    )
    saved = json.loads(args.review.read_text()) if args.apply else None
    if saved is not None:
        require(
            isinstance(saved, dict) and saved.get("transport") == transport,
            "saved snapshot review belongs to different SSH trust",
        )
        require(not saved.get("blockers"), "saved snapshot review contains blockers")
    administrative = {
        "admin_identity": args.admin_identity,
        "admin_agent_public_key": args.admin_agent_public_key,
        "known_hosts": args.known_hosts,
    }
    result = remote_call(
        manifest,
        "_snapshots-configure" if args.apply else "_snapshots-review",
        payload={"transport": transport},
        review_digest=saved["reviewDigest"] if saved else None,
        **administrative,
    )
    if args.apply and manifest["control"]["enable"]:
        try:
            catalog = remote_call(
                manifest, "_control-review", payload=None, **administrative
            )
            published = remote_call(
                manifest,
                "_control-publish",
                payload=None,
                review_digest=catalog["reviewDigest"],
                **administrative,
            )
        except (ValueError, OSError, subprocess.TimeoutExpired) as error:
            raise SnapshotError(
                "snapshot schedule was applied, but control catalog publication failed; "
                "retain the schedule and retry with a fresh review: " + str(error)
            ) from error
        result["catalogUpdated"] = True
        result["controlSnapshot"] = published.get("snapshot")
        result["snapshotsCreated"] = bool(
            (published.get("snapshot") or {}).get("created")
        )
    return result
