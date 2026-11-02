"""Reviewed creation of selected ZFS filesystems; never adopt or alter storage."""

import hashlib
import json
import os
from pathlib import Path, PurePosixPath


class StorageError(ValueError):
    """Unsafe, stale or incomplete filesystem provisioning."""


def require(condition, message):
    if not condition:
        raise StorageError(message)


def selected(manifest, principal, control):
    require(bool(principal) != bool(control), "select one principal or control storage")
    if control:
        cfg = manifest["control"]
        require(cfg["enable"], "control storage is disabled")
        result = {
            "name": cfg["dataset"],
            "mountpoint": cfg["path"],
            "quotaBytes": cfg["quotaBytes"],
            "uid": 0,
            "gid": 0,
        }
    else:
        owner = next(
            (p for p in manifest["principals"] if p["name"] == principal), None
        )
        require(owner is not None, "unknown storage principal")
        dataset = next(
            (d for d in manifest["datasets"] if d["name"] == owner["dataset"]), None
        )
        require(dataset is not None, "principal needs a declared dataset")
        result = dict(dataset, uid=owner["uid"], gid=owner["gid"])
    require(
        all(
            result[k] is not None
            for k in ("name", "mountpoint", "quotaBytes", "uid", "gid")
        ),
        "storage creation needs explicit dataset, mountpoint, quota and numeric ownership",
    )
    pool = manifest["pool"]["name"]
    require(result["name"].startswith(pool + "/"), "cannot provision the pool root")
    # Never create a parent above an existing principal's isolation boundary.
    names = [d["name"] for d in manifest["datasets"]]
    if manifest["control"]["dataset"]:
        names.append(manifest["control"]["dataset"])
    require(
        not any(
            n != result["name"]
            and (
                n.startswith(result["name"] + "/") or result["name"].startswith(n + "/")
            )
            for n in names
        ),
        "selected storage overlaps another managed dataset",
    )
    return result


def chain(manifest, state, target):
    root = next(
        (d for d in state["datasets"] if d["name"] == manifest["pool"]["name"]), None
    )
    require(
        root is not None and root["mounted"] and root["mountpoint"].startswith("/"),
        "pool root must already be mounted",
    )
    root_path = PurePosixPath(root["mountpoint"])
    pieces = target["name"].split("/")
    result = []
    for length in range(2, len(pieces) + 1):
        leaf = length == len(pieces)
        result.append(
            {
                "name": "/".join(pieces[:length]),
                "mountpoint": str(root_path.joinpath(*pieces[1:length])),
                "quotaBytes": target["quotaBytes"] if leaf else 0,
                "uid": target["uid"] if leaf else 0,
                "gid": target["gid"] if leaf else 0,
                "mode": 0o700 if leaf else 0o755,
            }
        )
    require(
        result[-1]["mountpoint"] == target["mountpoint"],
        "new storage mountpoint must follow the existing pool hierarchy",
    )
    return result


def observe(manifest, target, *, inspect, engine, backend):
    state = inspect(manifest)
    desired = chain(manifest, state, target)
    # Explicit native mounts prevent trusting ZFS properties over the actual VFS.
    state["storageMounts"] = [
        line.split()[:3] for line in engine.native(["/sbin/mount", "-p"]).splitlines()
    ]
    state["storagePaths"] = {}
    for item in desired:
        path = Path(item["mountpoint"])
        for ancestor in (*reversed(path.parents), path):
            if ancestor.exists() or ancestor.is_symlink():
                info = ancestor.lstat()
                state["storagePaths"][str(ancestor)] = {
                    "uid": info.st_uid,
                    "gid": info.st_gid,
                    "mode": info.st_mode & 0o7777,
                    "symlink": ancestor.is_symlink(),
                    "directory": ancestor.is_dir(),
                }
                backend.check_acl(ancestor)
    observed = {d["name"] for d in state["datasets"]}
    for item in desired:
        parts = item["name"].split("/")
        for length in range(1, len(parts) + 1):
            name = "/".join(parts[:length])
            if name in observed:
                state["delegations"][name] = engine.native(["/sbin/zfs", "allow", name])
    return state


def review(manifest, state, target, *, transport):
    desired = chain(manifest, state, target)
    blockers, actions = [], []
    if manifest["mode"] != "public":
        blockers.append("private mode is incomplete")
    if not manifest["pool"]["guid"] or state["pool"] != manifest["pool"]:
        blockers.append("pool name/GUID does not match approved storage")
    root = next(d for d in state["datasets"] if d["name"] == manifest["pool"]["name"])
    if [root["name"], root["mountpoint"], "zfs"] not in state["storageMounts"]:
        blockers.append("actual pool root mount differs from inspected ZFS storage")
    for user in state["users"]:
        if (
            target["uid"]
            and user["uid"] == target["uid"]
            and user["name"] != target.get("principal")
        ):
            blockers.append("reserved storage UID belongs to another account")
    for group in state["groups"]:
        if (
            target["gid"]
            and group["gid"] == target["gid"]
            and group["name"] != target.get("principal")
        ):
            blockers.append("reserved storage GID belongs to another group")
    if any(p["uid"] == target["uid"] for p in state["activeProcesses"]):
        blockers.append(
            "selected principal has running processes; quiesce before provisioning"
        )
    existing = {d["name"]: d for d in state["datasets"]}
    for item in desired:
        path = item["mountpoint"]
        for ancestor in PurePosixPath(path).parents:
            info = state["storagePaths"].get(str(ancestor))
            if info and (
                info["symlink"]
                or not info["directory"]
                or info["uid"] != 0
                or info["mode"] & 0o022
                or not info["mode"] & 0o001
            ):
                blockers.append(f"unsafe mountpoint ancestor: {ancestor}")
        actual = existing.get(item["name"])
        if actual is None:
            if path in state["storagePaths"]:
                blockers.append(f"refuse to mount over an existing path: {path}")
            actions.append(dict(kind="create-filesystem", **item))
            continue
        info = actual["metadata"]
        if (
            actual["mountpoint"] != path
            or not actual["mounted"]
            or [item["name"], path, "zfs"] not in state["storageMounts"]
            or not info.get("exists")
            or info.get("symlink")
            or (info.get("uid"), info.get("gid"), info.get("mode"))
            != (item["uid"], item["gid"], item["mode"])
            or actual["quotaBytes"] != item["quotaBytes"]
        ):
            blockers.append(
                f"existing storage differs; never adopt or change it: {item['name']}"
            )
    relevant = {manifest["pool"]["name"]} | {item["name"] for item in desired}
    if any(
        text.strip() for name, text in state["delegations"].items() if name in relevant
    ):
        blockers.append(
            "delegated ZFS permissions exist on selected storage or ancestors"
        )
    result = {
        "operation": "zfs-storage-initialization-review",
        "schemaVersion": 1,
        "target": target,
        "transport": transport,
        "state": state,
        "actions": actions,
        "blockers": sorted(set(blockers)),
        "createsPool": False,
        "altersExistingStorage": False,
    }
    result["reviewDigest"] = hashlib.sha256(
        json.dumps(
            {"manifest": manifest, "review": result},
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
    ).hexdigest()
    return result


def remote(manifest, *, payload, apply, expected_digest, inspect, engine):
    backend = engine.FreeBSD()
    backend.check()
    require(isinstance(payload, dict), "missing storage selection")
    require(
        set(payload) == {"principal", "control", "transport"},
        "invalid storage request fields",
    )
    target = selected(manifest, payload.get("principal"), payload.get("control", False))
    for executable in ("/sbin/zfs", "/sbin/zpool", "/sbin/mount"):
        engine.protected(executable)
    with engine.reconstruction_lock():
        state = observe(
            manifest, target, inspect=inspect, engine=engine, backend=backend
        )
        current = review(manifest, state, target, transport=payload.get("transport"))
        if not apply:
            return current
        require(
            current["reviewDigest"] == expected_digest,
            "storage review is stale or belongs to a different policy/trust; review again",
        )
        require(not current["blockers"], "storage review contains blockers")
        created = []
        try:
            for action in current["actions"]:
                path = Path(action["mountpoint"])
                engine.protected(path.parent, directory=True)
                require(
                    not path.exists() and not path.is_symlink(),
                    "mountpoint appeared after review",
                )
                engine.native(
                    [
                        "/sbin/zfs",
                        "create",
                        "-o",
                        "mountpoint=" + str(path),
                        "-o",
                        "quota="
                        + (
                            str(action["quotaBytes"])
                            if action["quotaBytes"]
                            else "none"
                        ),
                        "-o",
                        "reservation=none",
                        "-o",
                        "refreservation=none",
                        "-o",
                        "canmount=on",
                        "-o",
                        "readonly=off",
                        "-o",
                        "sharenfs=off",
                        "-o",
                        "sharesmb=off",
                        "-o",
                        "setuid=off",
                        "-o",
                        "devices=off",
                        action["name"],
                    ]
                )
                mounts = [
                    line.split()[:3]
                    for line in engine.native(["/sbin/mount", "-p"]).splitlines()
                ]
                require(
                    [action["name"], str(path), "zfs"] in mounts,
                    "new filesystem mount was not verified",
                )
                backend.check_acl(path)
                fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
                try:
                    os.fchmod(fd, action["mode"])
                    os.fchown(fd, action["uid"], action["gid"])
                finally:
                    os.close(fd)
                created.append(action["name"])
            after = observe(
                manifest, target, inspect=inspect, engine=engine, backend=backend
            )
            verified = review(
                manifest, after, target, transport=payload.get("transport")
            )
            require(
                not verified["blockers"] and not verified["actions"],
                "created storage did not match its declared state",
            )
        except (ValueError, OSError) as error:
            raise StorageError(
                f"storage initialization incomplete after {created!r}; partial filesystems retained; inspect before retry: {error}"
            ) from error
        return {
            "operation": "zfs-storage-initialization",
            "schemaVersion": 1,
            "createdDatasets": created,
            "changed": bool(created),
            "target": target,
        }


def initialize(args, manifest, *, remote_call, transport):
    require(args.apply or args.review is None, "--review is only used with --apply")
    require(
        not args.apply or args.review is not None,
        "storage init --apply requires a saved --review",
    )
    target = selected(manifest, args.principal, args.control)
    payload = {
        "principal": args.principal,
        "control": args.control,
        "transport": transport,
    }
    saved = json.loads(args.review.read_text()) if args.apply else None
    if saved is not None:
        require(
            saved.get("target") == target and saved.get("transport") == transport,
            "saved storage review has different selection or SSH trust",
        )
        require(not saved.get("blockers"), "saved storage review contains blockers")
    return remote_call(
        manifest,
        "_storage-init" if args.apply else "_storage-review",
        payload=payload,
        review_digest=saved["reviewDigest"] if saved else None,
        admin_identity=args.admin_identity,
        admin_agent_public_key=args.admin_agent_public_key,
        known_hosts=args.known_hosts,
    )
