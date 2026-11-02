"""Exercise initrd copying using real ELF notes and isolated fake ABI names."""

import json
import os
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path


class DlopenTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.libraries = self.root / "libraries"
        self.libraries.mkdir()
        self.binary = self.root / "program"
        source = self.root / "main.c"
        source.write_text("int main(void) { return 0; }\n")
        subprocess.run(
            [
                os.environ["CC"],
                str(source),
                "-o",
                str(self.binary),
                f"-Wl,-rpath,{self.libraries}",
            ],
            check=True,
        )

    def copy_with_note(self, alternatives):
        payload = (
            json.dumps(
                [{"soname": alternatives, "priority": "required", "feature": "test"}]
            ).encode()
            + b"\0"
        )
        note = self.root / "note"
        note.write_bytes(
            struct.pack("<III", 4, len(payload), 0x407C0C0A)
            + b"FDO\0"
            + payload
            + bytes((-len(payload)) % 4)
        )
        subprocess.run(
            [
                "objcopy",
                "--add-section",
                f".note.dlopen={note}",
                "--set-section-alignment",
                ".note.dlopen=4",
                str(self.binary),
            ],
            check=True,
        )
        manifest = self.root / "input.json"
        manifest.write_text(
            json.dumps(
                [
                    {
                        "source": str(self.binary),
                        "dlopen": {"usePriority": "required", "features": []},
                    }
                ]
            )
        )
        output = self.root / "initrd"
        output.mkdir()
        process = subprocess.run(
            [os.environ["INITRD_TOOL"], str(manifest), str(output)],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        return process, output

    def test_fallback_is_copied_without_spurious_warning(self):
        fallback = self.libraries / "libfallback.so.1"
        fallback.write_bytes(b"fixture")
        process, output = self.copy_with_note(["libpreferred.so.2", fallback.name])
        self.assertEqual(process.stderr, "")
        self.assertEqual((output / fallback.relative_to("/")).read_bytes(), b"fixture")

    def test_first_available_abi_is_selected(self):
        preferred = self.libraries / "libpreferred.so.2"
        fallback = self.libraries / "libfallback.so.1"
        preferred.write_bytes(b"preferred")
        fallback.write_bytes(b"fallback")
        process, output = self.copy_with_note([preferred.name, fallback.name])
        self.assertEqual(process.stderr, "")
        self.assertTrue((output / preferred.relative_to("/")).exists())
        self.assertFalse((output / fallback.relative_to("/")).exists())

    def test_unavailable_alternatives_are_still_reported(self):
        process, _ = self.copy_with_note(["libabsent.so.2", "libabsent.so.1"])
        self.assertIn(
            "Warning: Couldn't satisfy dependency libabsent.so.2 or libabsent.so.1",
            process.stderr,
        )
        self.assertEqual(process.stderr.count("Warning:"), 1)


if __name__ == "__main__":
    unittest.main()
