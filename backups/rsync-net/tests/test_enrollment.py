"""Exercise real source-local SSH keys and the administrative review boundary."""

import argparse
import ast
import copy
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import test_planner as fixtures

from rsync_net import cli as planner
from rsync_net import enrollment as controller

ROOT = Path(__file__).resolve().parents[1]
KEYGEN = shutil.which("ssh-keygen")


def test_scoped_bootstrap_keeps_only_selected_identity_and_storage():
    manifest = planner.validate(fixtures.policy())
    selected = planner.scoped_principal(manifest, "backup-source")
    planner.validate(selected)
    assert [p["name"] for p in selected["principals"]] == ["backup-source"]
    assert [d["name"] for d in selected["datasets"]] == ["data1/user"]
    assert len(manifest["principals"]) == len(manifest["datasets"]) == 2
    for field in ("connection", "pool", "setup", "control", "recovery"):
        assert selected[field] == manifest[field]
    try:
        planner.scoped_principal(manifest, "missing")
    except planner.PolicyError:
        pass
    else:
        raise AssertionError("unknown bootstrap principal was accepted")


def evaluate_modules(*modules, success=True):
    expressions = [
        "(builtins.fromJSON " + controller.nix_string(json.dumps(module)) + ")"
        if isinstance(module, dict)
        else json.dumps(str(module))
        for module in (ROOT / "module.nix", *modules)
    ]
    expression = (
        "let lib = import "
        + json.dumps(os.environ["RSYNC_NET_NIX_LIB"])
        + "; m = lib.evalModules { modules = [ "
        + " ".join(expressions)
        + " ]; }; in m.config.rsyncNet.manifest"
    )
    result = subprocess.run(
        ["nix-instantiate", "--eval", "--strict", "--json", "--expr", expression],
        env=dict(os.environ, NIX_REMOTE="dummy://"),
        capture_output=True,
        text=True,
        check=False,
    )
    if not success:
        assert result.returncode != 0, "invalid recovery configuration evaluated"
        return None
    assert result.returncode == 0, result.stderr
    return planner.validate(json.loads(result.stdout))


class EnrollmentTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="rsync-enrollment-test-")
        self.root = Path(self.folder.name)
        self.key = self.root / "private/device"
        self.args = argparse.Namespace(
            principal="git-repo",
            device="source-a",
            key_file=self.key,
            public_key=None,
            gpg_fingerprint="A" * 40,
            read_only=False,
            output=self.root / "review",
            new_account=True,
            backend="git",
            uid=3000,
            gid=3000,
            dataset="data1/git-repo",
            dataset_label=None,
            quota_bytes=1000000,
            purpose=None,
        )
        self.policy = fixtures.policy()
        planner.validate(self.policy)

    def tearDown(self):
        self.folder.cleanup()

    def enroll(self):
        return controller.enroll(
            self.args, self.policy, validate=planner.validate, keygen=KEYGEN
        )

    def module_policy(self):
        return {
            "rsyncNet": {
                "connection": self.policy["connection"],
                "pool": self.policy["pool"],
                "recovery": self.policy["recovery"],
                "principals": {
                    p["name"]: {k: v for k, v in p.items() if k != "readOnlyKeys"}
                    for p in self.policy["principals"]
                },
                "datasets": {d["name"]: d for d in self.policy["datasets"]},
                "control": self.policy["control"],
            }
        }

    def test_real_key_and_public_config_are_idempotent(self):
        first = self.enroll()
        private_before = self.key.read_bytes()
        public_before = Path(str(self.key) + ".pub").read_bytes()
        outputs_before = {p.name: p.read_bytes() for p in self.args.output.iterdir()}
        second = self.enroll()
        self.assertTrue(first["localDeviceKeyCreated"])
        self.assertFalse(second["localDeviceKeyCreated"])
        self.assertEqual(private_before, self.key.read_bytes())
        self.assertEqual(public_before, Path(str(self.key) + ".pub").read_bytes())
        self.assertEqual(
            outputs_before, {p.name: p.read_bytes() for p in self.args.output.iterdir()}
        )
        self.assertEqual(stat.S_IMODE(self.key.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.key.parent.stat().st_mode), 0o700)
        joined = b"\n".join(outputs_before.values())
        self.assertNotIn(b"PRIVATE KEY", joined)
        self.assertNotIn(str(self.key).encode(), joined)
        self.assertIn(b'devices."source-a"', outputs_before["enrollment.nix"])
        reviewed = planner.validate(json.loads(outputs_before["manifest.json"]))
        principal = next(p for p in reviewed["principals"] if p["name"] == "git-repo")
        self.assertEqual(principal["gcryptParticipants"], ["A" * 40])
        self.assertEqual(len(principal["publicKeys"]), 1)

    def test_other_machine_public_key_does_not_create_a_private_key(self):
        source_key = self.root / "source-identity"
        controller.device_key(source_key, "git-repo", "other-source", KEYGEN)
        self.args.key_file = None
        self.args.public_key = Path(str(source_key) + ".pub")
        result = self.enroll()
        self.assertFalse(result["localDeviceKeyCreated"])
        self.assertFalse(self.key.exists())
        self.assertEqual(
            {p.name for p in self.args.output.iterdir()},
            {"enrollment.nix", "manifest.json", "enrollment.json"},
        )

    def test_declarative_public_symlink_enrollment_and_admin_selection(self):
        source_key = self.root / "source-identity"
        public, _ = controller.device_key(source_key, "git-repo", "source", KEYGEN)
        public_link = self.root / "managed-public-key"
        public_link.symlink_to(Path(str(source_key) + ".pub"))
        self.args.key_file = None
        self.args.public_key = public_link
        result = self.enroll()
        self.assertFalse(result["localDeviceKeyCreated"])
        self.assertEqual(controller.public_file(public_link), public)
        self.assertEqual(
            controller.check_admin_file(public_link, private=False),
            public_link.resolve(),
        )
        with self.assertRaisesRegex(controller.EnrollmentError, "symlink"):
            controller.check_admin_file(public_link, private=True)

    def test_public_selector_rejects_private_or_malformed_key_material(self):
        controller.device_key(self.key, "git-repo", "source", KEYGEN)
        with self.assertRaises(controller.EnrollmentError):
            controller.check_admin_file(self.key, private=False)
        bad = self.root / "malformed.pub"
        bad.write_text("ssh-ed25519 YWJj\n")
        with self.assertRaisesRegex(controller.EnrollmentError, "encoding"):
            controller.public_file(bad)

    def test_existing_private_key_never_replaced_on_public_mismatch(self):
        self.enroll()
        before = self.key.read_bytes()
        Path(str(self.key) + ".pub").write_text(fixtures.public_key() + "\n")
        with self.assertRaisesRegex(controller.EnrollmentError, "does not match"):
            self.enroll()
        self.assertEqual(before, self.key.read_bytes())

    def test_missing_public_sidecar_is_recovered_from_existing_private(self):
        self.enroll()
        original = self.key.read_bytes()
        Path(str(self.key) + ".pub").unlink()
        self.assertFalse(self.enroll()["localDeviceKeyCreated"])
        self.assertEqual(original, self.key.read_bytes())
        self.assertTrue(Path(str(self.key) + ".pub").exists())

    def test_foreign_or_public_only_key_is_not_overwritten(self):
        self.key.parent.mkdir(mode=0o700)
        public_path = Path(str(self.key) + ".pub")
        public_path.write_text(fixtures.public_key())
        with self.assertRaisesRegex(
            controller.EnrollmentError, "public key exists without"
        ):
            self.enroll()
        self.assertFalse(self.key.exists())
        self.assertEqual(public_path.read_text(), fixtures.public_key())

    def test_symlink_and_git_private_paths_rejected(self):
        (self.root / ".git").mkdir()
        (self.root / ".git/HEAD").write_text("ref: refs/heads/test\n")
        with self.assertRaisesRegex(controller.EnrollmentError, "outside Git"):
            self.enroll()
        (self.root / ".git/HEAD").unlink()
        (self.root / ".git").rmdir()
        target = self.root / "target"
        target.mkdir(mode=0o700)
        self.key.parent.symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(controller.EnrollmentError, "symlink"):
            self.enroll()
        self.assertEqual(list(target.iterdir()), [])

    def test_world_readable_parent_or_existing_private_key_rejected(self):
        self.key.parent.mkdir(mode=0o755)
        with self.assertRaisesRegex(controller.EnrollmentError, "private permissions"):
            self.enroll()
        self.key.parent.chmod(0o700)
        self.enroll()
        self.key.chmod(0o644)
        with self.assertRaisesRegex(controller.EnrollmentError, "private regular file"):
            self.enroll()

    def test_missing_allocations_and_bad_gpg_fail_before_key_generation(self):
        for field, value in [
            ("uid", None),
            ("gpg_fingerprint", None),
            ("gpg_fingerprint", "ABC"),
            ("dataset", "data1/../escape"),
        ]:
            original = getattr(self.args, field)
            setattr(self.args, field, value)
            with self.assertRaises((controller.EnrollmentError, planner.PolicyError)):
                self.enroll()
            self.assertFalse(self.key.exists())
            setattr(self.args, field, original)

    def test_existing_principal_allocations_are_authoritative(self):
        self.args.principal = "nix-cache"
        with self.assertRaisesRegex(controller.EnrollmentError, "declared allocations"):
            self.enroll()
        self.assertFalse(self.key.exists())

    def test_shared_cache_enrollment_preserves_backend_policy(self):
        original = self.policy["principals"][0]
        base = self.module_policy()
        self.args.principal = original["name"]
        self.args.new_account = False
        self.args.gpg_fingerprint = None
        for field in ("backend", "uid", "gid", "dataset", "quota_bytes"):
            setattr(self.args, field, None)
        self.enroll()
        first = json.loads((self.args.output / "manifest.json").read_text())
        self.policy = first
        self.args.device = "builder-b"
        self.args.read_only = True
        self.args.key_file = self.root / "private/builder-b"
        self.args.output = self.root / "review-b"
        self.enroll()
        reviewed = json.loads((self.args.output / "manifest.json").read_text())
        cache = next(p for p in reviewed["principals"] if p["name"] == original["name"])
        self.assertEqual(cache["cache"], original["cache"])
        self.assertEqual(len(cache["publicKeys"]), 3)
        self.assertEqual(
            cache["readOnlyKeys"],
            [Path(str(self.args.key_file) + ".pub").read_text().strip()],
        )
        self.assertIn(
            "readOnly = true;", (self.args.output / "enrollment.nix").read_text()
        )
        self.assertIn(
            "nix-store --serve --store file:///mnt/data1/cache",
            planner.authorization(reviewed, cache),
        )
        self.assertEqual(cache["gcryptParticipants"], [])
        self.assertFalse(cache["recovery"]["enable"])
        self.assertIn(
            "nix-store --serve --write --store file:///mnt/data1/cache",
            planner.authorization(reviewed, cache),
        )
        public = (self.args.output / "enrollment.nix").read_text()
        self.assertNotIn("cache =", public)
        self.assertNotIn("signingPublicKeys", public)
        if os.environ.get("RSYNC_NET_NIX_LIB"):
            modules = [
                self.root / "review/enrollment.nix",
                self.root / "review-b/enrollment.nix",
            ]
            evaluated = evaluate_modules(base, *modules)
            actual = next(
                p for p in evaluated["principals"] if p["name"] == cache["name"]
            )
            self.assertEqual(actual, cache)
            base["rsyncNet"]["principals"][cache["name"]]["cache"][
                "signingPublicKeys"
            ] = []
            evaluated = evaluate_modules(base, *modules)
            self.assertEqual(
                next(p for p in evaluated["principals"] if p["name"] == cache["name"])[
                    "cache"
                ]["signingPublicKeys"],
                [],
            )

    def test_read_only_git_enrollment_and_restic_rejection(self):
        self.args.read_only = True
        self.enroll()
        reviewed = json.loads((self.args.output / "manifest.json").read_text())
        git = next(p for p in reviewed["principals"] if p["name"] == "git-repo")
        self.assertEqual(git["readOnlyKeys"], git["publicKeys"])
        self.assertIn("rrsync -ro -munge", planner.authorization(reviewed, git))
        if os.environ.get("RSYNC_NET_NIX_LIB"):
            evaluated = evaluate_modules(
                self.module_policy(), self.args.output / "enrollment.nix"
            )
            self.assertEqual(
                next(p for p in evaluated["principals"] if p["name"] == "git-repo"), git
            )
        self.args.backend = "restic"
        self.args.gpg_fingerprint = None
        self.args.purpose = "user"
        self.args.key_file = self.root / "private/rejected-restic"
        with self.assertRaisesRegex(controller.EnrollmentError, "read-only enrollment"):
            self.enroll()
        self.assertFalse(self.args.key_file.exists())

    def test_enrollment_does_not_change_existing_key_permissions(self):
        self.enroll()
        self.policy = json.loads((self.args.output / "manifest.json").read_text())
        self.args.new_account = False
        for field in ("backend", "uid", "gid", "dataset", "quota_bytes"):
            setattr(self.args, field, None)
        self.args.read_only = True
        self.args.output = self.root / "changed-permissions"
        with self.assertRaisesRegex(controller.EnrollmentError, "permission changes"):
            self.enroll()
        self.assertFalse(self.args.output.exists())

    def test_shared_git_membership_preserves_recovery_and_existing_devices(self):
        self.policy["recovery"] = {"enable": True, "recipients": ["C" * 40]}
        base = self.module_policy()
        self.enroll()
        first = json.loads((self.args.output / "manifest.json").read_text())
        self.policy = first
        self.args.new_account = False
        for field in ("backend", "uid", "gid", "dataset", "quota_bytes"):
            setattr(self.args, field, None)
        self.args.device = "source-b"
        self.args.key_file = self.root / "private/source-b"
        self.args.gpg_fingerprint = "B" * 40
        self.args.output = self.root / "review-b"
        self.enroll()
        reviewed = json.loads((self.args.output / "manifest.json").read_text())
        principal = next(p for p in reviewed["principals"] if p["name"] == "git-repo")
        self.assertEqual(principal["gcryptParticipants"], [x * 40 for x in "ABC"])
        self.assertEqual(len(principal["publicKeys"]), 2)
        self.assertEqual(principal["recovery"], first["recovery"])
        for folder in (self.root / "review", self.root / "review-b"):
            public = (folder / "enrollment.nix").read_text()
            self.assertNotIn("recovery =", public)
            self.assertNotIn("gcryptParticipants =", public)
            self.assertNotIn("PRIVATE KEY", public)
        if os.environ.get("RSYNC_NET_NIX_LIB"):
            imports = [
                self.root / "review/enrollment.nix",
                self.root / "review-b/enrollment.nix",
            ]

            def git_member():
                evaluated = evaluate_modules(base, *imports)
                return next(
                    p for p in evaluated["principals"] if p["name"] == "git-repo"
                )

            self.assertEqual(git_member(), principal)
            base["rsyncNet"]["recovery"]["recipients"] = ["D" * 40]
            self.assertEqual(
                git_member()["gcryptParticipants"], [x * 40 for x in "ABD"]
            )
            base["rsyncNet"]["principals"]["git-repo"] = {
                "recovery": {"recipients": ["E" * 40]}
            }
            self.assertEqual(
                git_member()["gcryptParticipants"], [x * 40 for x in "ABE"]
            )
            base["rsyncNet"]["principals"]["git-repo"]["recovery"]["enable"] = False
            self.assertEqual(git_member()["gcryptParticipants"], [x * 40 for x in "AB"])

    def test_existing_artifacts_are_not_replaced_with_another_device(self):
        self.enroll()
        before = {p.name: p.read_bytes() for p in self.args.output.iterdir()}
        self.args.device = "source-b"
        self.args.key_file = self.root / "private/source-b"
        with self.assertRaisesRegex(controller.EnrollmentError, "artifact differs"):
            self.enroll()
        self.assertEqual(
            before, {p.name: p.read_bytes() for p in self.args.output.iterdir()}
        )

    def test_bootstrap_private_identity_is_explicit_and_not_transmitted(self):
        self.enroll()
        args = argparse.Namespace(
            apply=False,
            admin_identity=self.key,
            admin_agent_public_key=None,
            known_hosts=self.root / "known_hosts",
        )
        captured = {}

        def inspect(policy, **options):
            captured.update(options)
            return fixtures.observed(policy)

        result = controller.bootstrap(
            args, self.policy, inspect_remote=inspect, plan=planner.plan
        )
        self.assertEqual(captured["admin_identity"], self.key)
        self.assertEqual(result["operation"], "administrative-bootstrap-review")
        self.assertNotIn(str(self.key), json.dumps(result))
        self.assertTrue(result["applySupported"])

    def test_apply_refuses_before_inspection_or_private_key_access(self):
        args = argparse.Namespace(
            apply=True,
            admin_identity=self.root / "absent",
            admin_agent_public_key=None,
            known_hosts=None,
        )
        with (
            patch.object(
                subprocess, "run", side_effect=AssertionError("no command should run")
            ),
            self.assertRaisesRegex(controller.EnrollmentError, "saved --review"),
        ):
            controller.bootstrap(args, self.policy, inspect_remote=None, plan=None)

    def test_private_apply_refuses_before_inspection_or_identity_access(self):
        manifest = copy.deepcopy(self.policy)
        manifest["mode"] = "private"
        args = argparse.Namespace(
            apply=True,
            review=self.root / "absent-review",
            admin_identity=self.root / "absent-identity",
            admin_agent_public_key=None,
            known_hosts=None,
        )
        with (
            patch.object(
                subprocess, "run", side_effect=AssertionError("no command should run")
            ),
            self.assertRaisesRegex(
                controller.EnrollmentError, "private mode is incomplete"
            ),
        ):
            controller.bootstrap(args, manifest, inspect_remote=None, plan=None)

    def test_ssh_invocation_does_not_offer_inherited_or_default_admin_keys(self):
        self.enroll()
        state = fixtures.observed(self.policy)

        def capture(manifest, remote, **options):
            command = planner.ssh_command(
                manifest,
                remote,
                **{
                    name: options[name]
                    for name in (
                        "admin_identity",
                        "admin_agent_public_key",
                        "known_hosts",
                    )
                },
            )
            self.assertEqual(command[command.index("-F") + 1], "/dev/null")
            self.assertIn("IdentitiesOnly=yes", command)
            self.assertIn("IdentityAgent=none", command)
            self.assertIn("StrictHostKeyChecking=yes", command)
            self.assertIn("ForwardAgent=no", command)
            self.assertIn("ClearAllForwardings=yes", command)
            self.assertNotIn("\n", command[-1])
            self.assertEqual(command[-1].count("'"), 2)
            self.assertNotIn(str(self.key), options["input"])
            self.assertNotIn(self.key.read_text(), options["input"])
            return subprocess.CompletedProcess(command, 0, json.dumps(state), "")

        with patch.object(planner, "remote_run", side_effect=capture):
            inspected = planner.inspect_remote(self.policy, admin_identity=self.key)
        self.assertEqual(inspected, state)

    def test_public_agent_selector_does_not_disable_selected_agent(self):
        self.enroll()
        public = Path(str(self.key) + ".pub")

        def capture(manifest, remote, **options):
            command = planner.ssh_command(
                manifest,
                remote,
                **{
                    name: options[name]
                    for name in (
                        "admin_identity",
                        "admin_agent_public_key",
                        "known_hosts",
                    )
                },
            )
            self.assertIn(str(public), command)
            self.assertIn("IdentitiesOnly=yes", command)
            self.assertNotIn("IdentityAgent=none", command)
            return subprocess.CompletedProcess(
                command, 0, json.dumps(fixtures.observed(self.policy)), ""
            )

        with patch.object(planner, "remote_run", side_effect=capture):
            planner.inspect_remote(self.policy, admin_agent_public_key=public)

    def test_cli_enroll_and_apply_gate(self):
        manifest = self.root / "policy.json"
        manifest.write_text(json.dumps(self.policy))
        command = [
            sys.executable,
            "-m",
            "rsync_net",
            "--manifest",
            str(manifest),
            "enroll",
            "--principal",
            "git-repo",
            "--device",
            "source-a",
            "--key-file",
            str(self.key),
            "--gpg-fingerprint",
            "A" * 40,
            "--output",
            str(self.args.output),
            "--new-account",
            "--backend",
            "git",
            "--uid",
            "3000",
            "--gid",
            "3000",
            "--dataset",
            "data1/git-repo",
            "--quota-bytes",
            "1000000",
        ]
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)["localDeviceKeyCreated"])
        apply_result = subprocess.run(
            [
                sys.executable,
                "-m",
                "rsync_net",
                "--manifest",
                str(manifest),
                "bootstrap",
                "--admin-identity",
                str(self.root / "absent"),
                "--apply",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(apply_result.returncode, 2)
        self.assertIn("saved --review", apply_result.stderr)

    def test_controller_sources_parse_with_freebsd_python_311_grammar(self):
        for source in (ROOT / "src/rsync_net").rglob("*.py"):
            ast.parse(source.read_text(), filename=str(source), feature_version=(3, 11))

    @unittest.skipUnless(
        os.environ.get("RSYNC_NET_NIX_LIB"),
        "Nix module evaluation runs in the native flake check",
    )
    def test_generated_public_module_round_trips_through_real_nix_types(self):
        self.enroll()
        from_nix = evaluate_modules(
            self.module_policy(), self.args.output / "enrollment.nix"
        )
        expected = planner.validate(
            json.loads((self.args.output / "manifest.json").read_text())
        )
        self.assertEqual(
            sorted(from_nix["principals"], key=lambda p: p["name"]),
            sorted(expected["principals"], key=lambda p: p["name"]),
        )
        self.assertEqual(
            sorted(from_nix["datasets"], key=lambda d: d["name"]),
            sorted(expected["datasets"], key=lambda d: d["name"]),
        )


@unittest.skipUnless(
    os.environ.get("RSYNC_NET_NIX_LIB"),
    "Nix module evaluation runs in the native flake check",
)
class ModuleRecoveryTest(unittest.TestCase):
    def test_framework_defaults_cover_encrypted_principals(self):
        manifest = evaluate_modules(
            ROOT / "tests/framework-policy.nix",
            {
                "rsyncNet": {
                    "principals": {
                        "user-backup": {"backend": "restic"},
                        "service-backup": {"backend": "restic"},
                        "shared-git": {"backend": "git"},
                        "nix-cache": {"backend": "nix-cache"},
                    }
                }
            },
        )
        self.assertTrue(manifest["recovery"]["enable"])
        self.assertTrue(manifest["recovery"]["recipients"])
        for principal in manifest["principals"]:
            self.assertEqual(
                principal["recovery"]["enable"], principal["backend"] != "nix-cache"
            )
            self.assertEqual(
                principal["recovery"]["recipients"], manifest["recovery"]["recipients"]
            )
            if principal["backend"] == "git":
                self.assertTrue(
                    set(manifest["recovery"]["recipients"]).issubset(
                        principal["gcryptParticipants"]
                    )
                )

    def test_named_cache_module_enforces_backend_boundaries(self):
        base = {
            "rsyncNet": {
                "connection": {"host": "fixture.example"},
                "principals": {
                    "cache-a": {"backend": "nix-cache"},
                    "cache-b": {"backend": "nix-cache"},
                    "git": {"backend": "git"},
                },
            }
        }
        result = evaluate_modules(base)
        planner.validate(result)
        self.assertEqual(
            [p["name"] for p in result["principals"] if p["backend"] == "nix-cache"],
            ["cache-a", "cache-b"],
        )
        wrong = copy.deepcopy(base)
        wrong["rsyncNet"]["principals"]["git"]["cache"] = {}
        evaluate_modules(wrong, success=False)

    def test_invalid_recovery_configuration_fails_module_evaluation(self):
        cases = [
            {"recovery": {"enable": True}},
            {"recovery": {"recipients": ["bad-fingerprint"]}},
            {"principals": {"git": {"backend": "git", "recovery": {"enable": True}}}},
            {
                "principals": {
                    "cache": {
                        "backend": "nix-cache",
                        "recovery": {"enable": True, "recipients": ["A" * 40]},
                    }
                }
            },
        ]
        for case in cases:
            with self.subTest(case=case):
                evaluate_modules(
                    {"rsyncNet": {"connection": {"host": "fixture.example"}, **case}},
                    success=False,
                )


if __name__ == "__main__":
    unittest.main()
