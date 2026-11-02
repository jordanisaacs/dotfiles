"""Exercise our recovery helper with native Restic and synthetic GPG recipients."""

import copy
import hashlib
import json
import os
import secrets
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from rsync_net import recovery

RESTIC = os.environ.get("RSYNC_NET_RESTIC") or shutil.which("restic")
GPG = os.environ.get("RSYNC_NET_GPG") or shutil.which("gpg")
GPGCONF = shutil.which("gpgconf")
if not (RESTIC and GPG and GPGCONF):
    raise RuntimeError(
        "native Restic, GPG and gpgconf are required for recovery regressions"
    )


class RecoveryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix="rsync-recovery-")
        cls.root = Path(cls.scratch.name)
        cls.homes = []
        cls.fingerprints = []
        for index in range(3):
            home = cls.root / f"gpg-{index}"
            home.mkdir(mode=0o700)
            cls.homes.append(home)
            cls.gpg(
                home,
                "--pinentry-mode",
                "loopback",
                "--passphrase",
                "",
                "--quick-generate-key",
                f"Recovery fixture {index} <fixture-{index}@example.invalid>",
                "ed25519",
                "cert",
                "0",
            )
            keys = cls.gpg(home, "--with-colons", "--list-keys")
            fingerprint = next(
                line.split(":")[9]
                for line in keys.decode().splitlines()
                if line.startswith("fpr:")
            )
            cls.fingerprints.append(fingerprint)
            cls.gpg(
                home,
                "--pinentry-mode",
                "loopback",
                "--passphrase",
                "",
                "--quick-add-key",
                fingerprint,
                "cv25519",
                "encr",
                "0",
            )
            cls.gpg(
                home,
                "--pinentry-mode",
                "loopback",
                "--passphrase",
                "",
                "--quick-add-key",
                fingerprint,
                "ed25519",
                "sign",
                "0",
            )
        cls.public = cls.root / "public-only"
        cls.public.mkdir(mode=0o700)
        cls.homes.append(cls.public)
        for home, fingerprint in zip(cls.homes[:2], cls.fingerprints[:2], strict=True):
            certificate = cls.gpg(home, "--export", fingerprint)
            cls.gpg(cls.public, "--import", input_data=certificate)
        for home in cls.homes[:3]:
            for source_home, fingerprint in zip(
                cls.homes[:3], cls.fingerprints, strict=True
            ):
                cls.gpg(
                    home,
                    "--import",
                    input_data=cls.gpg(source_home, "--export", fingerprint),
                )
        cls.password = secrets.token_urlsafe(32)
        cls.password_file = cls.root / "seed-password"
        cls.password_file.write_text(cls.password + "\n")
        cls.password_file.chmod(0o600)
        cls.seed = cls.root / "seed-repository"
        cls.data = cls.root / "data"
        cls.data.mkdir()
        (cls.data / "document.txt").write_text(
            "restore without the original device or password\n"
        )
        cls.restic(cls.seed, cls.password_file, "init")
        cls.restic(cls.seed, cls.password_file, "backup", cls.data)

    @classmethod
    def tearDownClass(cls):
        for home in cls.homes:
            subprocess.run(
                [GPGCONF, "--homedir", str(home), "--kill", "gpg-agent"],
                capture_output=True,
                check=False,
            )
        cls.scratch.cleanup()

    @staticmethod
    def gpg(home, *arguments, input_data=None, success=True):
        result = subprocess.run(
            [
                GPG,
                "--no-options",
                "--homedir",
                str(home),
                "--batch",
                "--no-tty",
                *map(str, arguments),
            ],
            input=input_data,
            capture_output=True,
            timeout=30,
            check=False,
        )
        if success:
            assert result.returncode == 0, result.stderr.decode()
            return result.stdout
        return result

    @staticmethod
    def restic(repo, password_file, *arguments):
        result = subprocess.run(
            [
                RESTIC,
                "--no-cache",
                "--json",
                "--repo",
                str(repo),
                "--password-file",
                str(password_file),
                *map(str, arguments),
            ],
            capture_output=True,
            timeout=60,
            check=False,
        )
        assert result.returncode == 0, result.stderr.decode()
        return result.stdout

    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(dir=self.root)
        self.work = Path(self.folder.name)
        self.repo = self.work / "repository"
        shutil.copytree(self.seed, self.repo)
        self.password_path = self.work / "operational-password"
        self.password_path.write_text(self.password + "\n")
        self.password_path.chmod(0o600)
        self.output = self.work / "bundle"
        self.principal = {
            "name": "backup-a",
            "backend": "restic",
            "dataset": "data1/backups/backup-a",
            "recovery": {"enable": True, "recipients": self.fingerprints[:2]},
        }

    def tearDown(self):
        self.folder.cleanup()

    def prepare(self, **overrides):
        arguments = {
            "repository": str(self.repo),
            "password_file": self.password_path,
            "output": self.output,
            "restic": RESTIC,
            "gpg": GPG,
            "gnupghome": self.homes[0],
            "signing_key": self.fingerprints[0],
        }
        arguments.update(overrides)
        return recovery.prepare(self.principal, **arguments)

    def keys(self):
        return {
            key["id"]
            for key in json.loads(
                self.restic(self.repo, self.password_path, "key", "list")
            )
        }

    def decrypt(self, home, ciphertext):
        return self.gpg(home, "--decrypt", input_data=ciphertext)

    def restore_with_password(self, password, destination):
        read_fd, write_fd = os.pipe()
        try:
            os.write(write_fd, password)
            os.close(write_fd)
            write_fd = None
            result = subprocess.run(
                [
                    RESTIC,
                    "--no-cache",
                    "--repo",
                    str(self.repo),
                    "--password-file",
                    f"/proc/self/fd/{read_fd}",
                    "restore",
                    "latest",
                    "--target",
                    str(destination),
                ],
                capture_output=True,
                pass_fds=(read_fd,),
                timeout=60,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr.decode())
        finally:
            os.close(read_fd)
            if write_fd is not None:
                os.close(write_fd)
        restored = destination / str(self.data).lstrip("/") / "document.txt"
        self.assertEqual(restored.read_text(), (self.data / "document.txt").read_text())

    def test_signed_prepare_and_two_recipients_restore_without_original_password(
        self,
    ):
        self.assertNotIn(
            b"sec:", self.gpg(self.public, "--with-colons", "--list-secret-keys")
        )
        before = self.keys()
        with self.assertRaisesRegex(
            recovery.RecoveryError, "signing/encryption failed"
        ):
            self.prepare(gnupghome=self.public)
        self.assertEqual(self.keys(), before)
        self.assertFalse((self.output / "recovery-password.asc").exists())
        result = self.prepare()
        self.assertTrue(result["changed"])
        self.assertFalse(result["restoreVerified"])
        self.assertEqual(self.keys() - before, {result["keyId"]})
        ciphertext = Path(result["ciphertextPath"]).read_bytes()
        first = recovery.decrypt_password(
            self.principal, self.output, gpg=GPG, gnupghome=self.homes[0]
        )
        second = recovery.decrypt_password(
            self.principal, self.output, gpg=GPG, gnupghome=self.homes[1]
        )
        self.assertEqual(first, second)
        self.assertNotEqual(first.strip().decode(), self.password)
        self.assertGreaterEqual(len(first.strip()), 43)
        self.assertNotIn(first.strip(), ciphertext)
        wrong = self.gpg(
            self.homes[2], "--decrypt", input_data=ciphertext, success=False
        )
        self.assertNotEqual(wrong.returncode, 0)
        self.password_path.unlink()
        restored = recovery.restore(
            self.principal,
            repository=str(self.repo),
            bundle=self.output,
            target=self.work / "replacement-client",
            restic=RESTIC,
            gpg=GPG,
            gnupghome=self.homes[1],
        )
        self.assertTrue(restored["restoreVerified"])
        document = (
            self.work
            / "replacement-client"
            / str(self.data).lstrip("/")
            / "document.txt"
        )
        self.assertEqual(document.read_text(), (self.data / "document.txt").read_text())
        self.assertNotIn(
            b"sec:", self.gpg(self.public, "--with-colons", "--list-secret-keys")
        )

    def test_password_command_prepares_recovery_without_operational_password_file(self):
        provider = self.work / "credential provider.py"
        provider.write_text(
            'import os, sys\nsys.stdout.write(os.environ["RSYNC_NET_TEST_PASSWORD"])\n'
        )
        command = shlex.join([sys.executable, str(provider)])
        self.password_path.unlink()
        with patch.dict(os.environ, {"RSYNC_NET_TEST_PASSWORD": self.password}):
            result = self.prepare(password_file=None, password_command=command)
            repeated = self.prepare(password_file=None, password_command=command)
        self.assertTrue(result["changed"])
        self.assertFalse(repeated["changed"])
        self.assertFalse(self.password_path.exists())
        for path in self.output.iterdir():
            self.assertNotIn(self.password.encode(), path.read_bytes())
        recovered = recovery.decrypt_password(
            self.principal, self.output, gpg=GPG, gnupghome=self.homes[1]
        )
        self.restore_with_password(recovered, self.work / "restored-from-command")

    def test_password_source_is_explicit_and_exclusive(self):
        for options in (
            {"password_file": None},
            {"password_command": "credential-provider"},
            {"password_file": None, "password_command": " "},
        ):
            with (
                self.subTest(options=options),
                self.assertRaises(recovery.RecoveryError),
            ):
                self.prepare(**options)
        self.assertFalse(self.output.exists())

    def test_failed_password_command_does_not_publish_or_leak_output(self):
        command = shlex.join(
            [
                sys.executable,
                "-c",
                'import sys; print("provider-private-output"); sys.exit(1)',
            ]
        )
        before = self.keys()
        with self.assertRaisesRegex(
            recovery.RecoveryError, "output was withheld"
        ) as error:
            self.prepare(password_file=None, password_command=command)
        self.assertNotIn("provider-private-output", str(error.exception))
        self.assertEqual(self.keys(), before)
        self.assertFalse(self.output.exists())

    def test_complete_bundle_is_idempotent_and_never_puts_passwords_in_argv_or_files(
        self,
    ):
        secret = "synthetic-recovery-password-" + secrets.token_urlsafe(32)
        commands = []
        actual_run = recovery.run

        def observed(arguments, **kwargs):
            commands.append(tuple(map(str, arguments)))
            self.assertNotIn(secret, repr(arguments))
            self.assertNotIn(self.password, repr(arguments))
            return actual_run(arguments, **kwargs)

        with (
            patch.object(recovery.secrets, "token_urlsafe", return_value=secret),
            patch.object(recovery, "run", side_effect=observed),
            patch.dict(
                os.environ,
                {
                    "RESTIC_PASSWORD": "incorrect inherited password",
                    "RESTIC_PASSWORD_FILE": "/must-not-read-inherited-password",
                    "RESTIC_PASSWORD_COMMAND": "this-command-must-not-run",
                    "RESTIC_REPOSITORY_FILE": "/must-not-read-inherited-repository",
                    "RESTIC_KEY_HINT": "0" * 64,
                },
            ),
        ):
            first = self.prepare()
            before = {path.name: path.read_bytes() for path in self.output.iterdir()}
            second = self.prepare()
        self.assertFalse(second["changed"])
        self.assertEqual(first["keyId"], second["keyId"])
        self.assertEqual(
            before, {path.name: path.read_bytes() for path in self.output.iterdir()}
        )
        for path in self.output.iterdir():
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertNotIn(secret.encode(), path.read_bytes())
            self.assertNotIn(self.password.encode(), path.read_bytes())
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o700)
        self.assertEqual(sum("add" in command for command in commands), 1)

    def test_invalid_policy_stops_before_native_commands_or_output_creation(self):
        for change in (
            {"backend": "git"},
            {"recovery": {"enable": False, "recipients": self.fingerprints[:1]}},
            {"recovery": {"enable": True, "recipients": []}},
            {"recovery": {"enable": True, "recipients": ["not-a-fingerprint"]}},
        ):
            with self.subTest(change=change):
                principal = copy.deepcopy(self.principal)
                self.principal.update(change)
                with (
                    patch.object(
                        recovery,
                        "run",
                        side_effect=AssertionError("native command was invoked"),
                    ),
                    self.assertRaises(recovery.RecoveryError),
                ):
                    self.prepare()
                self.principal = principal
                self.assertFalse(self.output.exists())

    def test_pending_ciphertext_survives_failure_after_native_key_addition(self):
        before = self.keys()
        actual_write = recovery.write_metadata

        def interrupted(path, value):
            if value["state"] == "complete":
                raise OSError("synthetic interruption after key addition")
            return actual_write(path, value)

        with (
            patch.object(recovery, "write_metadata", side_effect=interrupted),
            self.assertRaises(OSError),
        ):
            self.prepare()
        self.assertEqual(len(self.keys() - before), 1)
        metadata = json.loads((self.output / "recovery.json").read_text())
        self.assertEqual(metadata["state"], "pending")
        ciphertext = (self.output / "recovery-password.asc").read_bytes()
        recovered = json.loads(self.decrypt(self.homes[0], ciphertext))[
            "password"
        ].encode()
        self.assertTrue(recovered)
        artifacts = {p.name: p.read_bytes() for p in self.output.iterdir()}
        with self.assertRaisesRegex(recovery.RecoveryError, "pending recovery bundle"):
            self.prepare()
        self.assertEqual(
            artifacts, {p.name: p.read_bytes() for p in self.output.iterdir()}
        )
        self.assertEqual(len(self.keys() - before), 1)
        self.password_path.unlink()
        self.restore_with_password(recovered, self.work / "pending-recovery-client")

    def test_missing_recipient_certificate_and_insecure_password_cannot_add_keys(self):
        before = self.keys()
        self.principal["recovery"]["recipients"] = [self.fingerprints[0], "A" * 40]
        with self.assertRaisesRegex(
            recovery.RecoveryError, "GPG recovery signing/encryption failed"
        ):
            self.prepare()
        self.assertEqual(before, self.keys())
        self.assertFalse((self.output / "recovery-password.asc").exists())
        self.principal["recovery"]["recipients"] = self.fingerprints[:2]
        self.password_path.chmod(0o644)
        with self.assertRaisesRegex(recovery.RecoveryError, "private regular files"):
            self.prepare()
        self.password_path.chmod(0o600)
        self.assertEqual(before, self.keys())

    def test_read_and_save_fetched_bundle_are_immutable_and_validate_hash_policy(self):
        self.prepare()
        bundle = recovery.read_bundle(self.principal, self.output)
        destination = self.work / "fetched"
        first = recovery.save_bundle(
            self.principal,
            output=destination,
            metadata=bundle["metadata"],
            encrypted_password=bundle["encryptedPassword"],
        )
        second = recovery.save_bundle(
            self.principal,
            output=destination,
            metadata=bundle["metadata"],
            encrypted_password=bundle["encryptedPassword"],
        )
        self.assertTrue(first["changed"])
        self.assertFalse(second["changed"])
        self.assertEqual(recovery.read_bundle(self.principal, destination), bundle)
        metadata = copy.deepcopy(bundle["metadata"])
        metadata["ciphertextSha256"] = "0" * 64
        with self.assertRaisesRegex(recovery.RecoveryError, "recorded hash"):
            recovery.save_bundle(
                self.principal,
                output=destination,
                metadata=metadata,
                encrypted_password=bundle["encryptedPassword"],
            )
        changed = copy.deepcopy(self.principal)
        changed["recovery"]["recipients"] = self.fingerprints[:1]
        with self.assertRaisesRegex(recovery.RecoveryError, "recipient policy"):
            recovery.read_bundle(changed, destination)

    def forged_bundle(self, metadata, payload, *, signer=None):
        arguments = ["--trust-model", "always", "--armor"]
        if signer is not None:
            arguments += ["--local-user", signer, "--sign"]
        arguments += ["--encrypt"]
        for recipient in self.principal["recovery"]["recipients"]:
            arguments += ["--recipient", recipient]
        ciphertext = self.gpg(
            self.homes[2] if signer == self.fingerprints[2] else self.homes[0],
            *arguments,
            input_data=json.dumps(payload).encode(),
        )
        metadata = copy.deepcopy(metadata)
        metadata["ciphertextSha256"] = hashlib.sha256(ciphertext).hexdigest()
        destination = self.work / ("forged-" + secrets.token_hex(4))
        recovery.save_bundle(
            self.principal,
            output=destination,
            metadata=metadata,
            encrypted_password=ciphertext.decode(),
        )
        return destination

    def test_restore_rejects_unsigned_or_untrusted_server_forgery(self):
        result = self.prepare()
        metadata = json.loads(Path(result["metadataPath"]).read_text())
        payload = json.loads(
            self.decrypt(self.homes[0], Path(result["ciphertextPath"]).read_bytes())
        )
        for signer in (None, self.fingerprints[2]):
            with self.subTest(signer=signer):
                forged = self.forged_bundle(metadata, payload, signer=signer)
                target = self.work / ("must-not-exist-" + secrets.token_hex(4))
                with self.assertRaisesRegex(
                    recovery.RecoveryError, "unsigned or signed by an untrusted key"
                ):
                    recovery.restore(
                        self.principal,
                        repository=str(self.repo),
                        bundle=forged,
                        target=target,
                        restic=RESTIC,
                        gpg=GPG,
                        gnupghome=self.homes[0],
                    )
                self.assertFalse(target.exists())
        public_message = self.gpg(
            self.homes[0],
            "--armor",
            "--local-user",
            self.fingerprints[0],
            "--sign",
            input_data=json.dumps(payload).encode(),
        )
        public_metadata = {
            **metadata,
            "ciphertextSha256": hashlib.sha256(public_message).hexdigest(),
        }
        public_folder = self.work / "signed-but-not-encrypted"
        recovery.save_bundle(
            self.principal,
            output=public_folder,
            metadata=public_metadata,
            encrypted_password=public_message.decode(),
        )
        with self.assertRaisesRegex(
            recovery.RecoveryError, "not successfully decrypted"
        ):
            recovery.decrypt_password(
                self.principal, public_folder, gpg=GPG, gnupghome=self.homes[0]
            )

    def test_signed_scope_and_native_repository_identity_and_private_target_are_checked(
        self,
    ):
        result = self.prepare()
        metadata = json.loads(Path(result["metadataPath"]).read_text())
        payload = json.loads(
            self.decrypt(self.homes[0], Path(result["ciphertextPath"]).read_bytes())
        )
        wrong_scope = {**payload, "dataset": "data1/another-principal"}
        forged = self.forged_bundle(metadata, wrong_scope, signer=self.fingerprints[0])
        with self.assertRaisesRegex(
            recovery.RecoveryError, "signed recovery payload does not match"
        ):
            recovery.decrypt_password(
                self.principal, forged, gpg=GPG, gnupghome=self.homes[0]
            )
        other_repo = self.work / "other-repository"
        reader, writer = os.pipe()
        try:
            os.write(writer, payload["password"].encode() + b"\n")
            os.close(writer)
            writer = None
            initialized = subprocess.run(
                [
                    RESTIC,
                    "--repo",
                    str(other_repo),
                    "--password-file",
                    f"/proc/self/fd/{reader}",
                    "init",
                ],
                capture_output=True,
                pass_fds=(reader,),
                timeout=60,
                check=False,
            )
            self.assertEqual(initialized.returncode, 0)
        finally:
            os.close(reader)
            if writer is not None:
                os.close(writer)
        with self.assertRaisesRegex(
            recovery.RecoveryError, "actual Restic repository differs"
        ):
            recovery.restore(
                self.principal,
                repository=str(other_repo),
                bundle=self.output,
                target=self.work / "wrong-repo-target",
                restic=RESTIC,
                gpg=GPG,
                gnupghome=self.homes[0],
            )
        self.assertFalse((self.work / "wrong-repo-target").exists())
        nonempty = self.work / "existing-target"
        nonempty.mkdir(mode=0o700)
        (nonempty / "preserve").write_text("preserve this file")
        with self.assertRaisesRegex(recovery.RecoveryError, "new or empty"):
            recovery.restore(
                self.principal,
                repository=str(self.repo),
                bundle=self.output,
                target=nonempty,
                restic=RESTIC,
                gpg=GPG,
                gnupghome=self.homes[0],
            )
        self.assertEqual((nonempty / "preserve").read_text(), "preserve this file")

    def test_historical_signature_remains_recoverable_after_certificate_expiry(self):
        result = self.prepare()
        metadata = json.loads(Path(result["metadataPath"]).read_text())
        payload = self.decrypt(
            self.homes[0], Path(result["ciphertextPath"]).read_bytes()
        )
        home = self.root / "historic-recipient"
        home.mkdir(mode=0o700)
        self.homes.append(home)
        clock = ["--faked-system-time", "1577836800"]
        self.gpg(
            home,
            *clock,
            "--pinentry-mode",
            "loopback",
            "--passphrase",
            "",
            "--quick-generate-key",
            "Historic recovery <historic@example.invalid>",
            "ed25519",
            "cert,sign",
            "1d",
        )
        fingerprint = next(
            line.split(":")[9]
            for line in self.gpg(home, "--with-colons", "--list-keys")
            .decode()
            .splitlines()
            if line.startswith("fpr:")
        )
        self.gpg(
            home,
            *clock,
            "--pinentry-mode",
            "loopback",
            "--passphrase",
            "",
            "--quick-add-key",
            fingerprint,
            "cv25519",
            "encr",
            "1d",
        )
        ciphertext = self.gpg(
            home,
            *clock,
            "--trust-model",
            "always",
            "--armor",
            "--local-user",
            fingerprint,
            "--recipient",
            fingerprint,
            "--sign",
            "--encrypt",
            input_data=payload,
        )
        principal = copy.deepcopy(self.principal)
        principal["recovery"]["recipients"] = [fingerprint]
        metadata["recipients"] = [fingerprint]
        metadata["ciphertextSha256"] = hashlib.sha256(ciphertext).hexdigest()
        folder = self.work / "historical-bundle"
        recovery.save_bundle(
            principal,
            output=folder,
            metadata=metadata,
            encrypted_password=ciphertext.decode(),
        )
        password = recovery.decrypt_password(principal, folder, gpg=GPG, gnupghome=home)
        self.assertEqual(password.decode(), json.loads(payload)["password"])

    def test_restore_refuses_a_shared_nonsticky_ancestor_before_reading_secrets(self):
        unsafe = self.work / "shared-parent"
        unsafe.mkdir(mode=0o700)
        unsafe.chmod(0o777)
        target = unsafe / "restore"
        with self.assertRaisesRegex(
            recovery.RecoveryError, "ancestors cannot be writable"
        ):
            recovery.restore(
                self.principal,
                repository=str(self.repo),
                bundle=self.output,
                target=target,
                restic=RESTIC,
                gpg=GPG,
                gnupghome=self.homes[0],
            )
        self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
