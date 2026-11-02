"""Per-backup setup must finish recovery publication before reporting success."""

import copy
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from test_planner import policy

from rsync_net import backup, cli


def context(tmp_path):
    manifest = cli.validate(policy())
    owner = manifest["principals"][1]
    owner["recovery"] = {"enable": True, "recipients": ["A" * 40]}
    manifest["control"]["enable"] = True
    manifest["control"]["path"] = "/mnt/data1/control"
    job = {
        "schemaVersion": 1,
        "manifest": manifest,
        "principal": owner["name"],
        "repository": "rclone:ignored",
        "resticOptions": ["rclone.args=ignored"],
        "passwordFile": None,
        "passwordCommand": "credential-provider",
        "paths": ["/home/client/documents", "/home/client/photos"],
        "recoveryBundle": str(tmp_path / "recovery" / "backup-source"),
    }
    path = tmp_path / "job.json"
    path.write_text(json.dumps(job))
    args = SimpleNamespace(
        config=path,
        apply=False,
        review=None,
        signing_key=None,
        admin_identity=None,
        admin_agent_public_key=Path("/hardware.pub"),
        known_hosts=Path("/pinned/hosts"),
    )
    state = {"repositoryEntries": {owner["name"]: ["config", "keys"]}}
    metadata = {
        "principal": owner["name"],
        "repositoryId": "b" * 64,
        "keyId": "c" * 64,
        "recipients": ["A" * 40],
    }
    bundle = {"metadata": metadata, "encryptedPassword": "encrypted-signed-envelope"}
    events = []

    def remote(_manifest, operation, **_options):
        events.append(operation)
        if operation == "_storage-review":
            return {"actions": [], "blockers": []}
        if operation == "_inspect":
            return copy.deepcopy(state)
        if operation == "_control-review":
            return {"reviewDigest": "d" * 64}
        if operation == "_control-publish":
            return {"changed": True}
        if operation == "_control-fetch":
            return copy.deepcopy(bundle)
        raise AssertionError(operation)

    def native(arguments, **_options):
        events.append(arguments[-1])
        return json.dumps({"id": "b" * 64}).encode()

    def prepare(*_args, **_options):
        events.append("prepare-recovery")
        return {"changed": True}

    recovery = SimpleNamespace(
        run=Mock(side_effect=native),
        prepare=Mock(side_effect=prepare),
        read_bundle=Mock(return_value=bundle),
    )
    enrollment = SimpleNamespace(private_location=lambda p: p, private_parent=Mock())
    dependencies = {
        "load_helper": lambda kind: {"recovery": recovery, "enrollment": enrollment}[
            kind
        ],
        "remote_call": Mock(side_effect=remote),
        "validate": cli.validate,
        "plan": lambda *_: {"actions": [], "blockers": []},
        "transport": {"hostKey": "pinned"},
    }
    return manifest, job, args, state, events, recovery, dependencies


def reviewed(tmp_path):
    data = context(tmp_path)
    manifest, _job, args, _state, _events, _recovery, dependencies = data
    result = backup.setup(args, manifest, **dependencies)
    path = tmp_path / "review.json"
    path.write_text(json.dumps(result))
    args.review = path
    args.apply = True
    return data


def test_review_performs_no_initialization_signing_or_publication(tmp_path):
    manifest, _job, args, _state, events, recovery, dependencies = context(tmp_path)
    result = backup.setup(args, manifest, **dependencies)
    assert not result["blockers"]
    assert "publish" in result["phases"][-1]
    recovery.prepare.assert_not_called()
    assert "init" not in events and "_control-publish" not in events


def test_setup_reuses_repository_and_requires_recovery_round_trip(tmp_path):
    manifest, _job, args, _state, events, recovery, dependencies = reviewed(tmp_path)
    events.clear()
    result = backup.setup(args, manifest, **dependencies)
    assert result["setupComplete"] and result["recoveryPublished"]
    assert not result["repositoryInitialized"] and not result["restoreVerified"]
    assert (
        events.index("prepare-recovery")
        < events.index("_control-publish")
        < events.index("_control-fetch")
    )
    assert recovery.prepare.call_args.kwargs["signing_key"] == "A" * 40
    assert recovery.prepare.call_args.kwargs["password_file"] is None


def test_empty_repository_is_initialized_before_required_recovery(tmp_path):
    manifest, _job, args, state, events, recovery, dependencies = context(tmp_path)
    state["repositoryEntries"]["backup-source"] = []
    result = backup.setup(args, manifest, **dependencies)
    args.review = tmp_path / "review.json"
    args.review.write_text(json.dumps(result))
    args.apply = True
    events.clear()
    result = backup.setup(args, manifest, **dependencies)
    assert result["repositoryInitialized"]
    assert events.index("init") < events.index("prepare-recovery")
    assert recovery.prepare.call_count == 1


def test_stale_config_cannot_initialize_or_prepare_recovery(tmp_path):
    manifest, job, args, _state, events, recovery, dependencies = reviewed(tmp_path)
    job["paths"].append("/home/client/another-directory")
    args.config.write_text(json.dumps(job))
    events.clear()
    with pytest.raises(backup.BackupError, match="stale"):
        backup.setup(args, manifest, **dependencies)
    recovery.prepare.assert_not_called()
    assert "init" not in events and "_control-publish" not in events


def test_missing_escrow_or_failed_publication_never_reports_setup_complete(tmp_path):
    manifest, _job, args, _state, events, recovery, dependencies = reviewed(tmp_path)
    actual = dependencies["remote_call"].side_effect

    def failing(manifest, operation, **options):
        if operation == "_control-publish":
            raise ValueError("publication interrupted")
        return actual(manifest, operation, **options)

    dependencies["remote_call"].side_effect = failing
    with pytest.raises(backup.BackupError, match="incomplete.*retained"):
        backup.setup(args, manifest, **dependencies)
    recovery.prepare.assert_called_once()
    assert "_control-fetch" not in events


def test_descriptor_with_different_server_policy_fails_before_ssh(tmp_path):
    manifest, job, args, _state, _events, _recovery, dependencies = context(tmp_path)
    job["manifest"] = copy.deepcopy(job["manifest"])
    job["manifest"]["connection"]["host"] = "unapproved.invalid"
    args.config.write_text(json.dumps(job))
    with pytest.raises(backup.BackupError, match="authoritative"):
        backup.setup(args, manifest, **dependencies)
    dependencies["remote_call"].assert_not_called()
