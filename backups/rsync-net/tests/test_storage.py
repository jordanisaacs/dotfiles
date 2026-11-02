"""Regress reviewed ZFS creation without touching host pools or user data."""

import copy
from contextlib import nullcontext
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from test_planner import policy

from rsync_net import cli, storage


def fixture(root="/mnt/data1"):
    manifest = cli.validate(policy())
    owner = manifest["principals"][1]
    owner["dataset"] = "data1/backups/user"
    dataset = manifest["datasets"][1]
    dataset.update(name=owner["dataset"], mountpoint=root + "/backups/user")
    manifest["control"].update(
        enable=True, dataset="data1/control", path=root + "/control", quotaBytes=1048576
    )
    state = {
        "pool": manifest["pool"],
        "users": [],
        "groups": [],
        "activeProcesses": [],
        "delegations": {"data1": ""},
        "storagePaths": {},
        "storageMounts": [["data1", root, "zfs"]],
        "datasets": [
            {
                "name": "data1",
                "mountpoint": root,
                "mounted": True,
                "quotaBytes": 0,
                "metadata": {
                    "exists": True,
                    "uid": 0,
                    "gid": 0,
                    "mode": 0o755,
                    "symlink": False,
                },
            }
        ],
    }
    target = storage.selected(manifest, "backup-source", False)
    return manifest, state, target


def test_control_and_backup_are_independent_explicit_allocations():
    manifest, state, target = fixture()
    review = storage.review(manifest, state, target, transport={})
    assert not review["blockers"]
    assert [a["name"] for a in review["actions"]] == [
        "data1/backups",
        "data1/backups/user",
    ]
    assert review["actions"][-1]["uid"] == 2001
    control = storage.selected(manifest, None, True)
    reviewed = storage.review(manifest, state, control, transport={})
    assert [a["name"] for a in reviewed["actions"]] == ["data1/control"]
    assert reviewed["actions"][0]["mode"] == 0o700
    manifest["control"]["quotaBytes"] = None
    with pytest.raises(storage.StorageError, match="explicit"):
        storage.selected(manifest, None, True)


@pytest.mark.parametrize(
    "mutation", ["pool", "delegation", "path", "uid", "ancestor", "mount"]
)
def test_unsafe_storage_blocks_before_any_creation(mutation):
    manifest, state, target = fixture()
    if mutation == "pool":
        state["pool"] = {"name": "data1", "guid": "different"}
    elif mutation == "delegation":
        state["delegations"]["data1"] = "user legacy create,mount"
    elif mutation == "path":
        state["storagePaths"][target["mountpoint"]] = {
            "uid": 0,
            "gid": 0,
            "mode": 0o755,
            "symlink": False,
            "directory": True,
        }
    elif mutation == "uid":
        state["users"].append({"name": "unrelated", "uid": target["uid"]})
    elif mutation == "ancestor":
        state["storagePaths"]["/mnt/data1/backups"] = {
            "uid": 123,
            "gid": 0,
            "mode": 0o777,
            "symlink": False,
            "directory": True,
        }
    else:
        state["storageMounts"] = []
    assert storage.review(manifest, state, target, transport={})["blockers"]


def engine_for(tmp_path, monkeypatch):
    root = tmp_path / "pool"
    root.mkdir()
    manifest, state, target = fixture(str(root))
    desired = storage.chain(manifest, state, target)
    calls = []
    owners = Mock()
    monkeypatch.setattr(storage.os, "fchown", owners)

    def native(arguments):
        calls.append(arguments)
        if arguments[:2] == ["/sbin/mount", "-p"]:
            return "\n".join(
                " ".join(row) + " rw 0 0" for row in state["storageMounts"]
            )
        assert arguments[:2] == ["/sbin/zfs", "create"]
        assert "quota=0" not in arguments, (
            "native ZFS requires quota=none for uncapped parents"
        )
        item = next(d for d in desired if d["name"] == arguments[-1])
        Path(item["mountpoint"]).mkdir()
        state["datasets"].append(
            {
                "name": item["name"],
                "mountpoint": item["mountpoint"],
                "mounted": True,
                "quotaBytes": item["quotaBytes"],
                "metadata": {
                    "exists": True,
                    "uid": item["uid"],
                    "gid": item["gid"],
                    "mode": item["mode"],
                    "symlink": False,
                },
            }
        )
        state["storageMounts"].append([item["name"], item["mountpoint"], "zfs"])
        return ""

    engine = SimpleNamespace(
        FreeBSD=lambda: SimpleNamespace(check=Mock(), check_acl=Mock()),
        native=native,
        protected=Mock(),
        reconstruction_lock=nullcontext,
    )
    monkeypatch.setattr(
        storage, "observe", lambda *_args, **_kwargs: copy.deepcopy(state)
    )
    payload = {
        "principal": "backup-source",
        "control": False,
        "transport": {"hostKey": "pinned"},
    }
    return manifest, state, target, engine, payload, calls, owners


def test_native_creation_is_scoped_and_second_run_is_idempotent(tmp_path, monkeypatch):
    manifest, state, target, engine, payload, calls, owners = engine_for(
        tmp_path, monkeypatch
    )
    reviewed = storage.remote(
        manifest,
        payload=payload,
        apply=False,
        expected_digest=None,
        inspect=Mock(),
        engine=engine,
    )
    assert calls == []
    result = storage.remote(
        manifest,
        payload=payload,
        apply=True,
        expected_digest=reviewed["reviewDigest"],
        inspect=Mock(),
        engine=engine,
    )
    assert result["createdDatasets"] == ["data1/backups", "data1/backups/user"]
    assert owners.call_args_list[-1].args[1:] == (2001, 2001)
    assert all(command[1] in {"create", "-p"} for command in calls)
    assert all("-p" not in command for command in calls if command[0] == "/sbin/zfs")
    calls.clear()
    reviewed = storage.remote(
        manifest,
        payload=payload,
        apply=False,
        expected_digest=None,
        inspect=Mock(),
        engine=engine,
    )
    assert reviewed["actions"] == []
    result = storage.remote(
        manifest,
        payload=payload,
        apply=True,
        expected_digest=reviewed["reviewDigest"],
        inspect=Mock(),
        engine=engine,
    )
    assert not result["changed"] and calls == []
    # Existing quotas/ownership drift must never become a zfs set or chown action.
    state["datasets"][-1]["quotaBytes"] += 1
    assert storage.review(manifest, state, target, transport={})["blockers"]


def test_stale_review_or_changed_trust_performs_no_native_mutation(
    tmp_path, monkeypatch
):
    manifest, state, target, engine, payload, calls, _owners = engine_for(
        tmp_path, monkeypatch
    )
    reviewed = storage.review(manifest, state, target, transport=payload["transport"])
    payload["transport"] = {"hostKey": "changed"}
    with pytest.raises(storage.StorageError, match="stale"):
        storage.remote(
            manifest,
            payload=payload,
            apply=True,
            expected_digest=reviewed["reviewDigest"],
            inspect=Mock(),
            engine=engine,
        )
    assert calls == []


def test_partial_creation_is_retained_and_never_rolled_back(tmp_path, monkeypatch):
    manifest, state, target, engine, payload, calls, _owners = engine_for(
        tmp_path, monkeypatch
    )
    reviewed = storage.review(manifest, state, target, transport=payload["transport"])
    original = engine.native

    def failing(arguments):
        if arguments[-1] == target["name"]:
            raise ValueError("native creation failed")
        return original(arguments)

    engine.native = failing
    with pytest.raises(storage.StorageError, match="partial filesystems retained"):
        storage.remote(
            manifest,
            payload=payload,
            apply=True,
            expected_digest=reviewed["reviewDigest"],
            inspect=Mock(),
            engine=engine,
        )
    assert (tmp_path / "pool/backups").is_dir()
    assert not any("destroy" in command for command in calls)
