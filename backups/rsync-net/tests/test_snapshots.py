"""Regress declared snapshot scopes, TTL expiry and reviewed cron installation."""

import copy
import hashlib
import json
from contextlib import nullcontext
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from test_enrollment import ROOT, evaluate_modules
from test_planner import policy

from rsync_net import cli, setup, snapshots


def fixture():
    manifest = cli.validate(policy())
    manifest["setup"]["snapshotting"] = True
    dataset = manifest["datasets"][1]
    dataset["snapshots"] = {
        "hourly": {"schedule": "15 * * * *", "retention": "48h"},
        "daily": {"schedule": "20 0 * * *", "retention": "30d"},
        "weekly": {"schedule": "25 0 * * 0", "retention": "12w"},
        "monthly": {"schedule": "30 0 1 * *", "retention": "1y"},
        "yearly": {"schedule": "35 0 1 1 *", "retention": "forever"},
    }
    state = {
        "pool": manifest["pool"],
        "cronRunning": True,
        "toolVersion": "zfsnap v2.0.0-beta3",
        "before": {"exists": False, "managed": True, "sha256": None, "mode": None},
        "delegations": {"data1": "", dataset["name"]: ""},
        "mounts": [[dataset["name"], dataset["mountpoint"], "zfs"]],
        "datasets": [
            {
                **dataset,
                "mounted": True,
                "metadata": {
                    "exists": True,
                    "symlink": False,
                    "uid": 2001,
                    "gid": 2001,
                    "mode": 0o700,
                },
            }
        ],
        # A live routine backup must not block an atomic snapshot schedule edit.
        "activeProcesses": [{"uid": 2001, "arguments": "rclone serve restic"}],
    }
    return manifest, state


def test_native_jobs_are_explicit_nonrecursive_and_exactly_filter_every_tier():
    manifest, state = fixture()
    result = snapshots.review(manifest, state, transport={})
    assert not result["blockers"]
    jobs = result["jobs"]
    assert {j["retention"] for j in jobs[:-1]} == {"48h", "30d", "12w", "1y", "forever"}
    for job in jobs:
        assert job["arguments"][-2:] == ["-R", "data1/user"]
        assert not {"-r", "-D", "-F", "-P"}.intersection(job["arguments"])
    cleanup = jobs[-1]
    # Native zfsnap ValidPrefix compares full prefixes for equality. A single
    # '-p rsync-net-' would silently leave all tiered snapshots unexpired.
    assert cleanup["arguments"][2:-2] == [
        "-p",
        "rsync-net-daily-",
        "-p",
        "rsync-net-hourly-",
        "-p",
        "rsync-net-monthly-",
        "-p",
        "rsync-net-weekly-",
        "-p",
        "rsync-net-yearly-",
    ]
    assert cleanup["schedule"] == "55 * * * *"
    assert result["content"].startswith(snapshots.HEADER)
    assert (
        len([line for line in result["content"].splitlines() if " root " in line]) == 6
    )
    assert "/usr/bin/lockf -k -t 0" in result["content"]


@pytest.mark.parametrize("value", ["*/2 * * * *", "0,30 0-23/2 * * 0,7", "35 0 1 1 *"])
def test_numeric_cron_accepts_native_ranges_lists_and_steps(value):
    cli.validate_snapshot_cron(value)


@pytest.mark.parametrize(
    "value",
    [
        "60 * * * *",
        "0 24 * * *",
        "0 0 0 * *",
        "0 0 1 13 *",
        "0 0 * * 8",
        "*/0 * * * *",
        "*/61 * * * *",
        "5/2 * * * *",
        "30-10 * * * *",
        "* * * * *\n* * * * * root reboot",
        "* * * * *%reboot",
        "@hourly",
        "0 * * * MON",
    ],
)
def test_cron_rejects_out_of_range_and_injected_content(value):
    with pytest.raises(cli.PolicyError, match="snapshot"):
        cli.validate_snapshot_cron(value)


@pytest.mark.parametrize(
    "field,value",
    [
        ("label", "a;reboot"),
        ("retention", "0h"),
        ("retention", "01d"),
        ("retention", "forever;reboot"),
        ("schedule", "0 25 * * *"),
    ],
)
def test_manifest_rejects_unsafe_snapshot_policy(field, value):
    manifest, _state = fixture()
    schedules = manifest["datasets"][1]["snapshots"]
    if field == "label":
        schedules[value] = schedules.pop("hourly")
    else:
        schedules["hourly"][field] = value
    with pytest.raises(cli.PolicyError, match="snapshot"):
        cli.validate(manifest)


@pytest.mark.parametrize(
    "mutation",
    [
        "pool",
        "cron",
        "tool",
        "setup",
        "foreign",
        "delegation",
        "mount",
        "quota",
        "owner",
    ],
)
def test_drift_or_unmanaged_authority_blocks_schedule_install(mutation):
    manifest, state = fixture()
    if mutation == "pool":
        state["pool"] = {"name": "data1", "guid": "other"}
    elif mutation == "cron":
        state["cronRunning"] = False
    elif mutation == "tool":
        state["toolVersion"] = None
    elif mutation == "setup":
        manifest["setup"]["snapshotting"] = False
    elif mutation == "foreign":
        state["before"].update(exists=True, managed=False)
    elif mutation == "delegation":
        state["delegations"]["data1"] = "user writer destroy,snapshot"
    elif mutation == "mount":
        state["mounts"] = []
    elif mutation == "quota":
        state["datasets"][0]["quotaBytes"] += 1
    else:
        state["datasets"][0]["metadata"]["uid"] = 0
    assert snapshots.review(manifest, state, transport={})["blockers"]


def test_host_prerequisite_is_independent_of_dataset_schedules():
    manifest = cli.validate(policy())
    assert "zfsnap2" not in setup.packages(manifest)
    manifest["setup"]["snapshotting"] = True
    assert "zfsnap2" in setup.packages(manifest)
    assert snapshots.jobs(manifest) == []


def test_production_nix_policy_evaluates_requested_retention_and_typed_fields():
    manifest = evaluate_modules(ROOT / "tests/framework-policy.nix")
    assert manifest["setup"]["snapshotting"]
    dataset = manifest["datasets"][0]
    assert dataset["name"] == "data1/backups/user/example"
    assert {name: tier["retention"] for name, tier in dataset["snapshots"].items()} == {
        "hourly": "48h",
        "daily": "30d",
        "weekly": "12w",
        "monthly": "1y",
        "yearly": "forever",
    }
    assert manifest["datasets"][1]["snapshots"] == dataset["snapshots"]
    assert manifest["datasets"][1]["purpose"] == "git"
    evaluate_modules(
        ROOT / "tests/framework-policy.nix",
        {
            "rsyncNet": {
                "datasets": {
                    "backup-user": {
                        "snapshots": {
                            "unsafe": {"schedule": "@hourly", "retention": "48h"},
                        }
                    }
                }
            },
        },
        success=False,
    )


def test_shared_defaults_cover_every_backend_and_allow_opt_out_or_override():
    source = {
        "rsyncNet": {
            "connection": {"host": "example.invalid"},
            "pool": {"guid": "12345"},
            "snapshotSchedules": {
                "hourly": {"schedule": "15 * * * *", "retention": "48h"}
            },
            "principals": {},
            "datasets": {},
        }
    }
    for index, (backend, purpose) in enumerate(
        (("restic", "user"), ("git", "git"), ("nix-cache", "cache"))
    ):
        name = "host-" + backend
        principal = {
            "backend": backend,
            "uid": 62000 + index,
            "gid": 62000 + index,
            "dataset": "data1/" + name,
        }
        if backend == "nix-cache":
            principal["cache"] = policy()["principals"][0]["cache"]
        source["rsyncNet"]["principals"][name] = principal
        source["rsyncNet"]["datasets"][name] = {
            "name": "data1/" + name,
            "mountpoint": "/mnt/data1/" + name,
            "principal": name,
            "purpose": purpose,
            "quotaBytes": 1048576,
        }
    inherited = evaluate_modules(source)
    assert {d["purpose"] for d in inherited["datasets"]} == {"user", "git", "cache"}
    assert all(
        d["snapshots"] == source["rsyncNet"]["snapshotSchedules"]
        for d in inherited["datasets"]
    )
    assert len(snapshots.jobs(inherited)) == 6
    source["rsyncNet"]["datasets"]["host-nix-cache"]["snapshots"] = {}
    source["rsyncNet"]["datasets"]["host-git"]["snapshots"] = {
        "daily": {"schedule": "0 0 * * *", "retention": "7d"},
    }
    changed = evaluate_modules(source)
    by_name = {d["principal"]: d["snapshots"] for d in changed["datasets"]}
    assert by_name["host-nix-cache"] == {}
    assert list(by_name["host-git"]) == ["daily"]
    assert list(by_name["host-restic"]) == ["hourly"]
    assert len(snapshots.jobs(changed)) == 4


def test_remote_applies_only_reviewed_cron_and_native_dry_runs(tmp_path, monkeypatch):
    manifest, state = fixture()
    cron = tmp_path / "rsync-net-snapshots"
    monkeypatch.setattr(snapshots, "CRON", cron)
    monkeypatch.setattr(snapshots, "observe", lambda *_a, **_kw: copy.deepcopy(state))

    def atomic_file(path, content, *, mode):
        changed = not path.exists() or path.read_text() != content
        path.write_text(content)
        path.chmod(mode)
        state["before"].update(
            exists=True,
            managed=True,
            mode=mode,
            sha256=hashlib.sha256(content.encode()).hexdigest(),
        )
        return changed

    engine = SimpleNamespace(
        FreeBSD=lambda: SimpleNamespace(check=Mock()),
        reconstruction_lock=nullcontext,
        native=Mock(),
        atomic_file=Mock(side_effect=atomic_file),
    )
    options = {
        "manifest": manifest,
        "payload": {"transport": {"key": "pinned"}},
        "inspect": Mock(),
        "engine": engine,
    }
    reviewed = snapshots.remote(**options, apply=False, expected_digest=None)
    engine.atomic_file.assert_not_called()
    assert not cron.exists()
    with pytest.raises(snapshots.SnapshotError, match="stale"):
        snapshots.remote(**options, apply=True, expected_digest="stale")
    engine.atomic_file.assert_not_called()
    applied = snapshots.remote(
        **options, apply=True, expected_digest=reviewed["reviewDigest"]
    )
    assert applied["changed"]
    assert not applied["snapshotsCreated"] and not applied["snapshotsDeleted"]
    assert all(call.args[0][2] == "-n" for call in engine.native.call_args_list)
    assert applied["verifiedSha256"] == state["before"]["sha256"]
    reviewed = snapshots.remote(**options, apply=False, expected_digest=None)
    assert not reviewed["changed"]
    assert not snapshots.remote(
        **options, apply=True, expected_digest=reviewed["reviewDigest"]
    )["changed"]
    # Disabling drops all snapshot AND expiry jobs; it doesn't delete snapshots.
    manifest["datasets"][1]["snapshots"] = {}
    reviewed = snapshots.remote(**options, apply=False, expected_digest=None)
    assert reviewed["jobs"] == []
    engine.native.reset_mock()
    snapshots.remote(**options, apply=True, expected_digest=reviewed["reviewDigest"])
    engine.native.assert_not_called()
    assert " root " not in cron.read_text()


def test_cli_publishes_catalog_only_after_successful_apply(tmp_path):
    manifest, _state = fixture()
    manifest["control"]["enable"] = True
    review = tmp_path / "review.json"
    review.write_text(
        json.dumps({"transport": {}, "reviewDigest": "approved", "blockers": []})
    )
    args = SimpleNamespace(
        apply=True,
        review=review,
        admin_identity=None,
        admin_agent_public_key="hardware.pub",
        known_hosts="known_hosts",
    )
    remote = Mock(side_effect=[{"changed": True}, {"reviewDigest": "catalog"}, {}])
    assert snapshots.configure(args, manifest, remote_call=remote, transport={})[
        "catalogUpdated"
    ]
    assert [call.args[1] for call in remote.call_args_list] == [
        "_snapshots-configure",
        "_control-review",
        "_control-publish",
    ]
    remote.reset_mock(side_effect=True)
    remote.side_effect = ValueError("native configure failed")
    with pytest.raises(ValueError, match="failed"):
        snapshots.configure(args, manifest, remote_call=remote, transport={})
    assert remote.call_count == 1
    remote.reset_mock(side_effect=True)
    remote.side_effect = [{"changed": False}, ValueError("catalog failed")]
    with pytest.raises(snapshots.SnapshotError, match="schedule was applied"):
        snapshots.configure(args, manifest, remote_call=remote, transport={})
