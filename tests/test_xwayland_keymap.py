"""Compile real XKB data, preserving bindings and supporting newer keysyms."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


class KeymapTests(unittest.TestCase):
    def compile(self, compiler, data, extra="", database=None):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.xkb"
            output = Path(directory) / "output.xkb"
            source.write_text(
                "xkb_keymap {\n"
                ' xkb_keycodes { include "evdev+aliases(qwerty)" };\n'
                ' xkb_types { include "complete" };\n'
                ' xkb_compat { include "complete" };\n'
                ' xkb_symbols { include "pc+us+inet(evdev)"\n' + extra + "\n };\n};\n"
            )
            environment = os.environ.copy()
            environment.pop("XKEYSYMDB", None)
            if database is not None:
                environment["XKEYSYMDB"] = str(database)
            process = subprocess.run(
                [
                    compiler,
                    "-xkb",
                    "-w",
                    "1",
                    f"-I{data}/share/X11/xkb",
                    str(source),
                    str(output),
                ],
                check=False,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(process.returncode, 0, process.stderr)
            return output.read_text(), process.stderr

    def test_complete_keymap_preserves_all_bindings_without_warnings(self):
        original, _ = self.compile(
            os.environ["ORIGINAL_COMPILER"], os.environ["ORIGINAL_DATA"]
        )
        corrected, warnings = self.compile(
            os.environ["COMPILER"], os.environ["KEYBOARD_DATA"]
        )
        self.assertEqual(warnings, "")
        self.assertEqual(corrected, original)
        self.assertIn("PC_SHIFT_SUPER_LEVEL2", corrected)
        self.assertIn("PC_CONTROL_SUPER_LEVEL2", corrected)
        self.assertIn("XF86Assistant", corrected)
        self.assertIn("XF86TouchpadToggle", corrected)

    def test_new_names_resolve_to_their_published_values(self):
        keysyms = json.loads(os.environ["KEYSYMS"])
        named = "\n".join(
            f"replace key <FK{index:02}> {{ [ {name} ] }};"
            for index, name in enumerate(keysyms, 1)
        )
        numeric = "\n".join(
            f"replace key <FK{index:02}> {{ [ 0x{value} ] }};"
            for index, value in enumerate(keysyms.values(), 1)
        )
        by_name, warnings = self.compile(
            os.environ["COMPILER"], os.environ["KEYBOARD_DATA"], named
        )
        by_number, numeric_warnings = self.compile(
            os.environ["COMPILER"], os.environ["KEYBOARD_DATA"], numeric
        )
        self.assertEqual(warnings, "")
        self.assertEqual(numeric_warnings, "")
        self.assertEqual(by_name, by_number)

    def test_user_database_is_honored(self):
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "XKeysymDB"
            database.write_text(
                Path(os.environ["KEYSYM_DB"]).read_text() + "AuditSymbol: 1008ffff\n"
            )
            named, warnings = self.compile(
                os.environ["COMPILER"],
                os.environ["KEYBOARD_DATA"],
                "replace key <FK01> { [ AuditSymbol ] };",
                database,
            )
            numeric, numeric_warnings = self.compile(
                os.environ["COMPILER"],
                os.environ["KEYBOARD_DATA"],
                "replace key <FK01> { [ 0x1008ffff ] };",
                database,
            )
            self.assertEqual(warnings, "")
            self.assertEqual(numeric_warnings, "")
            self.assertEqual(named, numeric)


if __name__ == "__main__":
    unittest.main()
