"""Exercise the broker policy compatibility transform on synthetic XML."""

import os
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

NORMALIZER = os.environ["DBUS_POLICY_NORMALIZER"]
LEGACY = """<?xml version="1.0"?>
<!DOCTYPE busconfig SYSTEM "busconfig.dtd">
<busconfig>
  <!-- Preserve all formatting and unrelated access policies. -->
  <type>session</type>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
  <includedir>/example/session.d</includedir>
</busconfig>
"""


class PolicyTests(unittest.TestCase):
    def transform(self, text):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "session.conf"
            path.write_text(text)
            process = subprocess.run(
                [sys.executable, NORMALIZER, str(path)],
                check=False,
                capture_output=True,
                text=True,
            )
            return process, path.read_text()

    def test_preserves_effective_permissions_and_unrelated_text(self):
        process, result = self.transform(LEGACY)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(
            result,
            LEGACY.replace(' eavesdrop="true"', "", 1).replace(
                'eavesdrop="true"', 'receive_sender="*"'
            ),
        )
        rules = ET.fromstring(result).findall("./policy/allow")
        self.assertEqual(
            [rule.attrib for rule in rules],
            [{"send_destination": "*"}, {"receive_sender": "*"}, {"own": "*"}],
        )

    def test_already_modern_policy_is_unchanged(self):
        modern = LEGACY.replace(' eavesdrop="true"', "", 1).replace(
            'eavesdrop="true"', 'receive_sender="*"'
        )
        process, result = self.transform(modern)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(result, modern)

    def test_unexpected_policy_is_rejected_without_writing(self):
        unexpected = LEGACY.replace(
            'send_destination="*"', 'send_destination="org.example"'
        )
        process, result = self.transform(unexpected)
        self.assertNotEqual(process.returncode, 0)
        self.assertEqual(result, unexpected)


if __name__ == "__main__":
    unittest.main()
