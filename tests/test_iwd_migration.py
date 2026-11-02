"""Synthetic migration checks; never read the machine's saved credentials."""

import contextlib
import importlib.util
import io
import os
import stat
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

spec = importlib.util.spec_from_file_location(
    "migrate_iwd",
    Path(__file__).resolve().parents[1] / "modules/system/networking/migrate-iwd.py",
)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "iwd"
        self.source.mkdir()
        self.destination = self.root / "wpa" / "imperative.conf"

    def profile(self, name, content):
        path = self.source / name
        path.write_text(content, encoding="utf-8")
        return path

    def test_known_wpa2_vector_and_wpa3_password(self):
        self.profile("IEEE.psk", "[Security]\nPassphrase=password\n")
        self.assertEqual(
            migration.migrate(self.source, self.destination)["imported"], 1
        )
        converted = self.destination.read_text()
        self.assertIn("ssid=49454545", converted)
        self.assertIn(
            "psk=f42c6fc52df0ebef9ebb4b90b38a5f902e83fe1b135a70e23aed762e9710a12e",
            converted,
        )
        self.assertIn("sae_password=70617373776f7264", converted)
        self.assertNotIn('psk="password"', converted)

    def test_permissions_and_originals_and_repeat(self):
        original = self.profile(
            "Cafe.open", "[Settings]\nHidden=true\nAutoConnect=false\n"
        )
        before = original.read_bytes()
        migration.migrate(self.source, self.destination)
        self.assertEqual(stat.S_IMODE(self.destination.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.destination.parent.stat().st_mode), 0o750)
        self.assertEqual(original.read_bytes(), before)
        converted = self.destination.read_bytes()
        self.profile("New.open", "")
        self.assertEqual(
            migration.migrate(self.source, self.destination),
            {"existing_configuration_preserved": 1},
        )
        self.assertEqual(self.destination.read_bytes(), converted)
        self.assertIn(b"scan_ssid=1", converted)
        self.assertIn(b"disabled=1", converted)

    def test_hex_ssid_and_escaped_password_are_encoded(self):
        self.profile(
            "=436166c3a9.psk",
            '[Security]\nPassphrase=\\squote"\\\\é tail \n',
        )
        migration.migrate(self.source, self.destination)
        converted = self.destination.read_text()
        self.assertIn("ssid=436166c3a9", converted)
        self.assertIn("sae_password=" + ' quote"\\é tail '.encode().hex(), converted)
        self.assertNotIn('quote"', converted)

    def test_unsupported_security_and_privacy_are_skipped(self):
        self.profile("Enterprise.8021x", "[Security]\nEAP-Method=TLS\n")
        self.profile("Encrypted.psk", "[Security]\nEncryptedSecurity=secret\n")
        self.profile(
            "Identified.psk", "[Security]\nPassphrase=password\nPasswordIdentifier=id\n"
        )
        self.profile("Private.open", "[Settings]\nAlwaysRandomizeAddress=true\n")
        self.profile(
            "Strict.psk",
            "[Settings]\nTransitionDisable=true\n[Security]\nPassphrase=password\n",
        )
        self.profile("=xx.open", "")
        self.assertEqual(
            migration.migrate(self.source, self.destination),
            {"imported": 0, "manual_configuration_required": 6},
        )
        self.assertEqual(len(list(self.source.iterdir())), 6)

    def test_preserve_existing_and_reject_symlink_destination(self):
        self.destination.parent.mkdir()
        self.destination.write_text("existing configuration\n")
        migration.migrate(self.source, self.destination)
        self.assertEqual(self.destination.read_text(), "existing configuration\n")
        self.destination.unlink()
        other = self.root / "other"
        other.write_text("untouched")
        self.destination.symlink_to(other)
        with self.assertRaises(OSError):
            migration.migrate(self.source, self.destination)
        self.assertEqual(other.read_text(), "untouched")

    def test_status_output_contains_counts_without_credentials(self):
        self.profile("PrivateSSID.psk", "[Security]\nPassphrase=private-secret\n")
        settings = {"source": str(self.source), "destination": str(self.destination)}
        account = types.SimpleNamespace(pw_uid=os.getuid(), pw_gid=os.getgid())
        output = io.StringIO()
        with (
            mock.patch.object(migration, "CONFIG", settings, create=True),
            mock.patch.object(migration.pwd, "getpwnam", return_value=account),
            contextlib.redirect_stdout(output),
        ):
            migration.main()
        self.assertIn("imported=1", output.getvalue())
        self.assertNotIn("PrivateSSID", output.getvalue())
        self.assertNotIn("private-secret", output.getvalue())


if __name__ == "__main__":
    unittest.main()
