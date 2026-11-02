"""Control helper regressions with real private files and injected native probes.

The unprivileged fixture adapter is confined to this test file. Production uses
the root-only FreeBSD adapter; the native FreeBSD VM exercises real mounted
ZFS and native root authority checks.
"""

import base64
import copy
import json
import os
import shutil
import stat
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path

from rsync_net import control


def armor(marker=b"fixture"):
    # This tests the server's packet envelope checks, not GPG cryptography.
    packets = b"\xc1\x14" + b"s" * 20 + b"\xd2" + bytes([len(marker)]) + marker
    return (
        "-----BEGIN PGP MESSAGE-----\n\n"
        + base64.b64encode(packets).decode()
        + "\n-----END PGP MESSAGE-----\n"
    )


class Backend:
    label = "FreeBSD"

    def __init__(self):
        self.allowed = True
        self.denied_acl = None

    def check(self):
        if not self.allowed:
            raise ValueError("wrong platform/privilege")

    def check_acl(self, path):
        if path == self.denied_acl:
            raise ValueError("nontrivial ACL")


class Engine:
    def __init__(self, root):
        self.root = root
        self.mount_source = "zfs data1/control"
        self.delegations = ""
        self.writes = 0
        self.fail_write = None
        self.locked = False
        self.snapshots = []
        self.fail_snapshot = False

    def protected(self, path, *, directory=False):
        for item in (*path.parents, path):
            if item != self.root and self.root not in item.parents:
                continue
            if item.is_symlink():
                raise ValueError("authority symlink")
            if item.exists():
                info = item.stat()
                if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o022:
                    raise ValueError("uncontrolled authority")
        if path.exists() and (path.is_dir() if directory else path.is_file()) is False:
            raise ValueError("wrong authority type")

    def native(self, command):
        if Path(command[0]).name == "mount":
            fstype, source = self.mount_source.split()
            return f"{source} {self.root} {fstype} rw 0 0\n"
        if Path(command[0]).name == "zfs" and command[1] == "allow":
            return self.delegations
        if command[:2] == ["/sbin/zfs", "list"]:
            assert command[-1] == "data1/control"
            return "\n".join(self.snapshots)
        if command[:2] == ["/sbin/zfs", "snapshot"]:
            assert self.locked
            assert len(command) == 3 and command[2].startswith(
                "data1/control@rsync-net-control-"
            )
            if self.fail_snapshot:
                raise ValueError("simulated snapshot failure")
            target = self.root / ".zfs/snapshot" / command[2].split("@", 1)[1]
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            (self.root / ".zfs").chmod(0o700)
            shutil.copytree(self.root, target, ignore=shutil.ignore_patterns(".zfs"))
            self.snapshots.append(command[2])
            return ""
        raise AssertionError(command)

    @contextmanager
    def reconstruction_lock(self):
        if self.locked:
            raise ValueError("another bootstrap is running")
        self.locked = True
        try:
            yield
        finally:
            self.locked = False

    def atomic_file(self, path, content, *, mode):
        self.protected(path)
        if path.exists() and path.read_text() == content:
            return False
        if path == self.fail_write:
            raise OSError("simulated publication interruption")
        # Publication ordering belongs to this helper. Atomic replacement and
        # native root ownership belong to the real engine exercised in VMs.
        path.write_text(content)
        path.chmod(mode)
        self.writes += 1
        return True


class ControlTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "control"
        self.root.mkdir(mode=0o700)
        self.engine, self.backend = Engine(self.root), Backend()
        self.manifest = {
            "schemaVersion": 1,
            "control": {"enable": True, "path": str(self.root)},
            "pool": {"name": "data1", "guid": "123456"},
            "principals": [
                {
                    "name": "laptop",
                    "backend": "restic",
                    "dataset": "data1/laptop",
                    "recovery": {"enable": True, "recipients": ["A" * 40]},
                }
            ],
            "datasets": [{"mountpoint": str(self.root.parent / "laptop")}],
        }
        self.state = {
            "system": "FreeBSD",
            "pool": copy.deepcopy(self.manifest["pool"]),
            "datasets": [
                {"name": "data1/control", "mountpoint": str(self.root), "mounted": True}
            ],
            "delegations": {"data1": ""},
        }
        self.payload = {
            "principal": "laptop",
            "repositoryId": "a" * 64,
            "keyId": "b" * 64,
            "recipients": ["A" * 40],
            "encryptedPassword": armor(),
        }
        self.dependencies = {
            "validate": lambda value: value,
            "inspect": lambda _: self.state,
            "engine": self.engine,
            "backend": self.backend,
        }

    def review(self, payload=None):
        return control.review(self.manifest, payload, **self.dependencies)

    def publish(self, payload=None):
        review = self.review(payload)
        return control.publish(
            self.manifest,
            payload,
            expected_digest=review["reviewDigest"],
            **self.dependencies,
        )

    def test_review_is_readonly_and_does_not_expose_ciphertext(self):
        review = self.review(self.payload)
        self.assertEqual(self.engine.writes, 0)
        self.assertEqual(list(self.root.iterdir()), [])
        self.assertNotIn("encryptedPassword", json.dumps(review))
        self.assertNotIn("PGP MESSAGE", json.dumps(review))
        self.assertEqual(len(review["reviewDigest"]), 64)

    def test_publish_fetch_and_idempotence(self):
        result = self.publish(self.payload)
        self.assertEqual(len(result["changes"]), 3)
        self.assertTrue(result["snapshot"]["created"])
        self.assertTrue(result["snapshot"]["verified"])
        bundle = control.fetch(self.manifest, "laptop", **self.dependencies)
        self.assertEqual(bundle["encryptedPassword"], self.payload["encryptedPassword"])
        self.assertEqual(bundle["metadata"]["keyId"], "b" * 64)
        self.assertFalse(bundle["metadata"]["restoreVerified"])
        catalog = control.fetch(self.manifest, **self.dependencies)["catalog"]
        self.assertEqual(catalog["manifest"], self.manifest)
        self.assertEqual(catalog["repositories"]["laptop"], bundle["metadata"])
        self.assertEqual(self.publish(self.payload)["changes"], [])
        self.assertEqual(len(self.engine.snapshots), 1)
        self.assertFalse(self.publish(self.payload)["snapshot"]["created"])
        for path in self.root.rglob("*"):
            self.assertEqual(
                stat.S_IMODE(path.stat().st_mode), 0o700 if path.is_dir() else 0o600
            )

    def test_stale_review_refuses_writes(self):
        review = self.review(self.payload)
        self.publish()
        before = self.engine.writes
        with self.assertRaisesRegex(ValueError, "stale"):
            control.publish(
                self.manifest,
                self.payload,
                expected_digest=review["reviewDigest"],
                **self.dependencies,
            )
        self.assertEqual(self.engine.writes, before)

    def test_replacement_or_changed_binding_is_refused(self):
        self.publish(self.payload)
        for field, value in (
            ("encryptedPassword", armor(b"replacement")),
            ("keyId", "c" * 64),
            ("repositoryId", "d" * 64),
        ):
            candidate = dict(self.payload, **{field: value})
            with (
                self.subTest(field=field),
                self.assertRaisesRegex(ValueError, "replaced"),
            ):
                self.review(candidate)

    def test_partial_publish_retries_original_bundle_only(self):
        self.engine.fail_write = self.root / "recovery/laptop.json"
        with self.assertRaisesRegex(OSError, "interruption"):
            self.publish(self.payload)
        self.assertEqual(
            (self.root / "recovery/laptop.asc").read_text(),
            self.payload["encryptedPassword"],
        )
        with self.assertRaisesRegex(ValueError, "incomplete"):
            self.review()
        self.engine.fail_write = None
        self.assertEqual(len(self.publish(self.payload)["changes"]), 2)

    def test_policy_rotation_keeps_old_bundle_fetchable(self):
        self.publish(self.payload)
        self.manifest["principals"][0]["recovery"] = {
            "enable": False,
            "recipients": ["B" * 40],
        }
        bundle = control.fetch(self.manifest, "laptop", **self.dependencies)
        self.assertEqual(bundle["metadata"]["recipients"], ["A" * 40])
        self.assertEqual(self.publish()["changes"], ["published public catalog"])
        catalog = control.fetch(self.manifest, **self.dependencies)["catalog"]
        self.assertEqual(catalog["manifest"], self.manifest)
        self.assertEqual(catalog["repositories"]["laptop"], bundle["metadata"])
        self.assertEqual(len(self.engine.snapshots), 2)

    def test_snapshot_failure_retains_files_and_retry_completes_without_rewriting(self):
        self.engine.fail_snapshot = True
        with self.assertRaisesRegex(
            control.ControlError, "files were published.*snapshot is incomplete"
        ):
            self.publish(self.payload)
        assert (self.root / "catalog.json").exists()
        assert self.engine.snapshots == []
        writes = self.engine.writes
        self.engine.fail_snapshot = False
        result = self.publish(self.payload)
        assert result["changes"] == []
        assert result["snapshot"]["created"] and result["snapshot"]["verified"]
        assert self.engine.writes == writes

    def test_existing_snapshot_must_contain_the_completed_catalog_and_envelopes(self):
        result = self.publish(self.payload)
        frozen = (
            self.root / ".zfs/snapshot" / result["snapshot"]["name"].split("@", 1)[1]
        )
        (frozen / "recovery/laptop.asc").write_text(armor(b"incorrect"))
        with self.assertRaisesRegex(control.ControlError, "does not match"):
            self.publish(self.payload)

    def test_hardlinked_control_files_are_rejected(self):
        self.publish(self.payload)
        os.link(self.root / "recovery/laptop.asc", self.root / "duplicate.asc")
        with self.assertRaisesRegex(ValueError, "single-link"):
            self.review()

    def test_publication_serializes_with_other_administration(self):
        review = self.review(self.payload)
        with (
            self.engine.reconstruction_lock(),
            self.assertRaisesRegex(ValueError, "another bootstrap"),
        ):
            control.publish(
                self.manifest,
                self.payload,
                expected_digest=review["reviewDigest"],
                **self.dependencies,
            )
        self.assertEqual(self.engine.writes, 0)

    def test_unselected_or_missing_control_storage_never_creates_it(self):
        self.manifest["control"]["path"] = None
        with self.assertRaisesRegex(ValueError, "unselected"):
            self.review(self.payload)
        missing = self.root / "missing"
        self.manifest["control"]["path"] = str(missing)
        with self.assertRaisesRegex(ValueError, "already exist"):
            self.review(self.payload)
        self.assertFalse(missing.exists())

    def test_catalog_fetch_rejects_unexpected_secret_fields(self):
        self.publish(self.payload)
        path = self.root / "catalog.json"
        catalog = json.loads(path.read_text())
        catalog["repositories"]["laptop"]["password"] = "never-return-this"
        path.write_text(json.dumps(catalog))
        with self.assertRaisesRegex(ValueError, "metadata"):
            control.fetch(self.manifest, **self.dependencies)

    def test_identity_mount_and_delegation_guards(self):
        mutations = (
            ("wrong pool", lambda: self.state["pool"].update(guid="9876")),
            ("unmounted", lambda: self.state["datasets"][0].update(mounted=False)),
            ("overlay", lambda: setattr(self.engine, "mount_source", "tmpfs tmpfs")),
            (
                "other dataset",
                lambda: setattr(self.engine, "mount_source", "zfs data1/other"),
            ),
            (
                "delegated",
                lambda: setattr(self.engine, "delegations", "user laptop snapshot"),
            ),
            ("wrong privilege", lambda: setattr(self.backend, "allowed", False)),
        )
        for name, mutate in mutations:
            with self.subTest(name=name):
                old_state = copy.deepcopy(self.state)
                mutate()
                with self.assertRaises(ValueError):
                    self.review(self.payload)
                self.assertEqual(self.engine.writes, 0)
                self.state = old_state
                (
                    self.engine.mount_source,
                    self.engine.delegations,
                    self.backend.allowed,
                ) = "zfs data1/control", "", True

    def test_permissions_symlinks_acl_and_repo_overlap(self):
        self.root.chmod(0o755)
        with self.assertRaisesRegex(ValueError, "0700"):
            self.review(self.payload)
        self.root.chmod(0o700)
        self.backend.denied_acl = self.root
        with self.assertRaisesRegex(ValueError, "ACL"):
            self.review(self.payload)
        self.backend.denied_acl = None
        self.manifest["datasets"][0]["mountpoint"] = str(self.root / "client")
        with self.assertRaisesRegex(ValueError, "separate"):
            self.review(self.payload)
        self.manifest["datasets"][0]["mountpoint"] = str(self.root.parent / "laptop")
        (self.root / "catalog.json").symlink_to(self.root.parent / "missing")
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.review(self.payload)

    def test_private_files_and_checksum_are_checked(self):
        self.publish(self.payload)
        envelope = self.root / "recovery/laptop.asc"
        envelope.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "private"):
            control.fetch(self.manifest, "laptop", **self.dependencies)
        envelope.chmod(0o600)
        envelope.write_text(armor(b"tampered"))
        with self.assertRaisesRegex(ValueError, "inconsistent"):
            control.fetch(self.manifest, "laptop", **self.dependencies)

    def test_rejects_plaintext_private_keys_unbound_or_unexpected_upload(self):
        mutations = (
            {"encryptedPassword": "password=do-not-store"},
            {
                "encryptedPassword": "-----BEGIN PGP PRIVATE KEY BLOCK-----\nsecret\n-----END PGP PRIVATE KEY BLOCK-----\n"
            },
            {"recipients": ["B" * 40]},
            {"principal": "../laptop"},
            {"keyId": "short"},
            {"password": "never"},
        )
        for changes in mutations:
            with self.subTest(changes=list(changes)), self.assertRaises(ValueError):
                self.review(dict(self.payload, **changes))
            self.assertEqual(self.engine.writes, 0)

    def test_rejects_unencrypted_or_symmetric_pgp_packet_stream(self):
        for binary in (
            b"\xcb\x03abc",
            b"\xc3\x01x\xd2\x01y",
            b"\xc1\xff",
            b"\xc1\x64x",
        ):
            candidate = (
                "-----BEGIN PGP MESSAGE-----\n\n"
                + base64.b64encode(binary).decode()
                + "\n-----END PGP MESSAGE-----\n"
            )
            with self.assertRaises(ValueError):
                control.encrypted_message(candidate)

    def test_freebsd_mount_probe_and_escaped_paths(self):
        self.backend.label = self.state["system"] = "FreeBSD"
        self.review(self.payload)
        self.engine.native = lambda arguments: (
            (
                "data1/control "
                + str(self.root).replace("control", r"contr\157l")
                + " zfs rw 0 0\n"
            )
            if Path(arguments[0]).name == "mount"
            else ""
        )
        self.review(self.payload)


if __name__ == "__main__":
    unittest.main()
