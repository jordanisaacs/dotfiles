"""Exercise policy boundaries without privileged commands or a live server."""

import base64
import copy
import json
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from rsync_net import cli as planner


def public_key():
    algorithm = b"ssh-ed25519"
    wire = (
        struct.pack("!I", len(algorithm))
        + algorithm
        + struct.pack("!I", 32)
        + b"x" * 32
    )
    return "ssh-ed25519 " + base64.b64encode(wire).decode()


def policy():
    return {
        "schemaVersion": 1,
        "connection": {
            "host": "example.invalid",
            "user": "root",
            "port": 22,
            "interpreter": "/usr/local/bin/python3.11",
        },
        "pool": {"name": "data1", "guid": "123456"},
        "recovery": {"enable": False, "recipients": []},
        "control": {"enable": False, "path": None},
        "principals": [
            {
                "name": "nix-cache",
                "uid": 2000,
                "gid": 2000,
                "home": "/home/nix-cache",
                "backend": "nix-cache",
                "cache": {
                    "signingPublicKeys": [
                        "cache-test:" + base64.b64encode(b"p" * 32).decode()
                    ],
                },
                "dataset": "data1/cache",
                "publicKeys": [public_key()],
                "readOnlyKeys": [],
                "gcryptParticipants": [],
                "recovery": {"enable": False, "recipients": []},
            },
            {
                "name": "backup-source",
                "uid": 2001,
                "gid": 2001,
                "home": "/home/backup-source",
                "backend": "restic",
                "cache": None,
                "dataset": "data1/user",
                "publicKeys": [public_key()],
                "readOnlyKeys": [],
                "gcryptParticipants": [],
                "recovery": {"enable": False, "recipients": []},
            },
        ],
        "datasets": [
            {
                "name": "data1/cache",
                "mountpoint": "/mnt/data1/cache",
                "principal": "nix-cache",
                "purpose": "cache",
                "quotaBytes": 1000000,
            },
            {
                "name": "data1/user",
                "mountpoint": "/mnt/data1/user",
                "principal": "backup-source",
                "purpose": "user",
                "quotaBytes": 1000000,
            },
        ],
    }


def observed(manifest):
    users = [
        {
            "name": p["name"],
            "uid": p["uid"],
            "gid": p["gid"],
            "home": p["home"],
            "shell": "/bin/sh",
            "groups": [p["gid"]],
            "passwordAuthDisabled": True,
        }
        for p in manifest["principals"]
    ]
    groups = [
        {"name": p["name"], "gid": p["gid"], "members": []}
        for p in manifest["principals"]
    ]
    files = {
        path: {"exists": True, "uid": 0, "gid": 0, "mode": 0o755, "symlink": False}
        for path in (
            "/",
            "/home",
            "/usr",
            "/usr/local",
            "/usr/local/etc",
            "/usr/local/etc/rsync-net",
            str(planner.AUTHORIZATION_ROOT),
        )
    }
    for p in manifest["principals"]:
        for suffix in ("", "/.ssh"):
            path = p["home"] + suffix
            files[path] = {
                "exists": True,
                "uid": 0,
                "gid": 0,
                "mode": 0o755,
                "symlink": False,
            }
        for suffix in ("authorized_keys", "authorized_keys2"):
            files[p["home"] + "/.ssh/" + suffix] = {"exists": False}
        authorized = str(planner.authorization_path(p))
        files[authorized] = {
            "exists": True,
            "uid": 0,
            "gid": 0,
            "mode": 0o644,
            "symlink": False,
        }
        files[authorized]["sha256"] = planner.hashlib.sha256(
            planner.authorization(manifest, p).encode()
        ).hexdigest()
        backend = planner.backend_config(p)
        if backend is not None:
            files[str(backend[0])] = {
                "exists": True,
                "uid": 0,
                "gid": 0,
                "mode": 0o644,
                "symlink": False,
                "sha256": planner.hashlib.sha256(backend[1].encode()).hexdigest(),
            }
    files[str(planner.PRIVATE_SSHD_CONFIG)] = {
        "exists": True,
        "uid": 0,
        "gid": 0,
        "mode": 0o600,
        "symlink": False,
        "sha256": planner.hashlib.sha256(
            planner.private_sshd_config(manifest).encode()
        ).hexdigest(),
    }
    return {
        "schemaVersion": 1,
        "system": "FreeBSD",
        "pool": copy.deepcopy(manifest["pool"]),
        "users": users,
        "groups": groups,
        "files": files,
        "datasets": [
            {
                "name": d["name"],
                "mountpoint": d["mountpoint"],
                "mounted": True,
                "quotaBytes": d["quotaBytes"],
                "metadata": {
                    "exists": True,
                    "uid": next(
                        p["uid"]
                        for p in manifest["principals"]
                        if p["name"] == d["principal"]
                    ),
                    "gid": next(
                        p["gid"]
                        for p in manifest["principals"]
                        if p["name"] == d["principal"]
                    ),
                    "mode": 0o750,
                    "symlink": False,
                },
            }
            for d in manifest["datasets"]
        ],
        "packages": ["nix", "rclone"],
        "delegations": {},
        "activeProcesses": [],
    }


class RecoveryPlanTest(unittest.TestCase):
    def setUp(self):
        self.policy = policy()
        planner.validate(self.policy)
        self.state = observed(self.policy)

    def blockers(self):
        return "\n".join(planner.plan(self.policy, self.state)["blockers"])

    def test_matching_state_is_idempotent_plan_not_safety_claim(self):
        result = planner.plan(self.policy, self.state)
        self.assertEqual(result["actions"], [])
        self.assertEqual(result["blockers"], [])
        self.assertTrue(result["applySupported"])
        self.assertGreater(len(result["requiredVerification"]), 0)
        self.assertTrue(result["recovery"]["policyOnly"])
        self.assertFalse(result["recovery"]["provisioningVerified"])

    def test_invalid_or_inapplicable_recovery_policy_is_rejected(self):
        for mutate in (
            lambda p: p["recovery"].update(enable=True),
            lambda p: p["recovery"].update(recipients=["not-a-fingerprint"]),
            lambda p: p["principals"][1]["recovery"].update(enable=True),
            lambda p: p["principals"][0]["recovery"].update(
                enable=True, recipients=["C" * 40]
            ),
        ):
            manifest = policy()
            mutate(manifest)
            with self.assertRaises(planner.PolicyError):
                planner.validate(manifest)

    def test_wrong_pool_guid_blocks(self):
        self.state["pool"]["guid"] = "98765"
        self.assertIn("pool name or GUID", self.blockers())

    def test_inspected_absent_home_ancestor_can_be_reconstructed(self):
        self.state["users"] = []
        self.state["groups"] = []
        for path in self.state["files"]:
            if path == "/home" or path.startswith("/home/"):
                self.state["files"][path] = {"exists": False}
        result = planner.plan(self.policy, self.state)
        self.assertEqual(result["blockers"], [])
        self.assertTrue(
            any(
                action["kind"] == "restore-control-directory"
                and action["path"] == "/home"
                for action in result["actions"]
            )
        )

    def test_uninspected_or_absent_root_ancestor_blocks(self):
        for path in ("/", "/home", "/home/nix-cache/.ssh"):
            with self.subTest(path=path):
                state = copy.deepcopy(self.state)
                del state["files"][path]
                self.assertIn(
                    "was not inspected",
                    "\n".join(planner.plan(self.policy, state)["blockers"]),
                )
        self.state["files"]["/"] = {"exists": False}
        self.assertIn("root", self.blockers())

    def test_surviving_data_missing_os_state_produces_recovery_intent(self):
        self.state["users"] = []
        self.state["groups"] = []
        self.state["files"] = {
            key: value
            if key in {"/", "/home", "/usr", "/usr/local", "/usr/local/etc"}
            else {"exists": False}
            for key, value in self.state["files"].items()
        }
        self.state["packages"] = []
        with patch.object(
            subprocess,
            "run",
            side_effect=AssertionError("plan must not execute commands"),
        ):
            result = planner.plan(self.policy, self.state)
        self.assertEqual(result["blockers"], [])
        kinds = [a["kind"] for a in result["actions"]]
        self.assertEqual(kinds.count("create-user"), 2)
        self.assertEqual(kinds.count("create-group"), 2)
        self.assertEqual(kinds.count("restore-authorization"), 2)
        self.assertEqual(kinds.count("install-package"), 2)
        self.assertNotIn("destroy", json.dumps(result))

    def test_uid_and_gid_reuse_block(self):
        self.state["users"].append({"name": "unrelated", "uid": 2000})
        self.state["groups"].append({"name": "unrelated", "gid": 2001})
        text = self.blockers()
        self.assertIn("reserved UID belongs", text)
        self.assertIn("reserved GID belongs", text)

    def test_identity_and_supplementary_group_drift_block(self):
        self.state["users"][0]["groups"].append(0)
        self.assertIn("membership differs", self.blockers())
        self.state = observed(self.policy)
        self.state["groups"][0]["members"].append("unrelated")
        self.assertIn("unrelated members", self.blockers())

    def test_missing_or_unmounted_data_never_plans_creation(self):
        self.state["datasets"][0]["mounted"] = False
        self.assertIn("not mounted safely", self.blockers())
        self.state["datasets"] = []
        result = planner.plan(self.policy, self.state)
        self.assertIn("dataset absent", "\n".join(result["blockers"]))
        self.assertNotIn("zfs", json.dumps(result["actions"]))

    def test_data_ownership_and_quota_drift_never_auto_repaired(self):
        dataset = self.state["datasets"][0]
        dataset["metadata"]["uid"] = 2345
        dataset["quotaBytes"] = 0
        text = self.blockers()
        self.assertIn("never recursively chowns", text)
        self.assertIn("quota differs", text)

    def test_client_writable_and_symlink_enforcement_paths_block(self):
        self.state["files"]["/home/nix-cache"]["uid"] = 2000
        self.state["files"]["/home/nix-cache/.ssh"]["symlink"] = True
        text = self.blockers()
        self.assertIn("non-root-owned", text)
        self.assertIn("/home/nix-cache/.ssh", text)

    def test_cache_authority_is_owned_by_the_named_principal(self):
        principal = self.policy["principals"][0]
        command = planner.authorization(self.policy, principal)
        self.assertIn(
            "nix-store --serve --write --store file:///mnt/data1/cache", command
        )
        self.assertNotIn("/mnt/data1/user", command)
        self.assertNotIn("cache", self.policy)
        wrong = copy.deepcopy(self.policy)
        wrong["principals"][1]["cache"] = copy.deepcopy(principal["cache"])
        with self.assertRaisesRegex(planner.PolicyError, "cache settings require"):
            planner.validate(wrong)

    def test_device_readers_get_fixed_commands_and_cannot_change_backend(self):
        cache = self.policy["principals"][0]
        cache["readOnlyKeys"] = list(cache["publicKeys"])
        planner.validate(self.policy)
        command = planner.authorization(self.policy, cache)
        self.assertIn(
            "nix-store --serve --store file:///mnt/data1/cache --option builders ''",
            command,
        )
        self.assertNotIn("--write", command)
        cache["readOnlyKeys"] = [cache["publicKeys"][0] + " absent"]
        with self.assertRaisesRegex(planner.PolicyError, "subset"):
            planner.validate(self.policy)
        cache["readOnlyKeys"] = []
        backup = self.policy["principals"][1]
        backup["readOnlyKeys"] = list(backup["publicKeys"])
        with self.assertRaisesRegex(planner.PolicyError, "append-only"):
            planner.validate(self.policy)
        backup["readOnlyKeys"] = []
        cache["readOnlyKeys"] = list(cache["publicKeys"])
        cache["publicKeys"].append(cache["publicKeys"][0] + " other-comment")
        with self.assertRaisesRegex(planner.PolicyError, "conflicting"):
            planner.validate(self.policy)

    def test_named_caches_share_ssh_and_control_paths_stay_separate(self):
        extra = copy.deepcopy(self.policy["principals"][0])
        extra.update(
            name="other-cache",
            uid=2002,
            gid=2002,
            home="/home/other-cache",
            dataset=None,
        )
        self.policy["principals"].append(extra)
        planner.validate(self.policy)
        self.policy["principals"].pop()
        for path in (
            "/mnt/data1/cache/control",
            "/mnt/data1",
            "/mnt/data1/control/../escape",
        ):
            self.policy["control"] = {"enable": True, "path": path}
            with self.assertRaises(planner.PolicyError):
                planner.validate(self.policy)
        self.policy["control"] = {"enable": True, "path": None}
        self.assertIn("control: durable directory is not approved", self.blockers())

    def test_enforcement_ancestor_must_be_inspected_and_protected(self):
        self.state["files"].pop("/home")
        self.assertIn("ancestor /home was not inspected", self.blockers())
        self.state = observed(self.policy)
        self.state["files"]["/home"]["mode"] = 0o777
        self.assertIn("enforcement path /home", self.blockers())

    def test_unknown_commands_private_keys_and_non_loopback_rejected(self):
        for mutate in [
            lambda p: p.update({"command": "anything"}),
            lambda p: p["principals"][0]["cache"].update({"listenAddress": "0.0.0.0"}),
            lambda p: p["principals"][0].update(
                {"publicKeys": ["-----BEGIN OPENSSH PRIVATE KEY-----"]}
            ),
            lambda p: p["connection"].update({"interpreter": "/usr/bin/python;id"}),
            lambda p: p["principals"][0].update({"home": "/root"}),
        ]:
            manifest = policy()
            mutate(manifest)
            with self.assertRaises(planner.PolicyError):
                planner.validate(manifest)

    def test_role_cannot_point_at_another_security_boundary(self):
        self.policy["principals"][1]["dataset"] = "data1/cache"
        with self.assertRaisesRegex(planner.PolicyError, "another principal"):
            planner.validate(self.policy)

    def test_incomplete_allocations_remain_explicit_blockers(self):
        self.policy["principals"][0]["uid"] = None
        self.policy["datasets"][0]["quotaBytes"] = None
        self.policy["principals"][0]["cache"]["signingPublicKeys"] = []
        text = self.blockers()
        self.assertIn("UID/GID allocation", text)
        self.assertIn("quota allocation", text)
        self.assertIn("no approved public signing keys", text)

    def test_apply_refuses_before_reading_manifest(self):
        result = subprocess.run(
            [sys.executable, "-m", "rsync_net", "apply"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("apply is not implemented", result.stderr)

    def test_cli_validate_and_plan_outputs(self):
        with tempfile.TemporaryDirectory() as folder:
            manifest = Path(folder) / "policy.json"
            state = Path(folder) / "state.json"
            manifest.write_text(json.dumps(self.policy))
            state.write_text(json.dumps(self.state))
            for command in (["validate"], ["plan", "--state", str(state)]):
                result = subprocess.run(
                    [
                        sys.executable,
                        "-m",
                        "rsync_net",
                        "--manifest",
                        str(manifest),
                        *command,
                    ],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(json.loads(result.stdout)["applySupported"])


if __name__ == "__main__":
    unittest.main()
