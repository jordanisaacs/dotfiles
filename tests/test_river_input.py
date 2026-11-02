"""Check device profiles against channel's actual pinned native glob matcher."""

import json
import os
import subprocess
import tarfile
from pathlib import Path


def zig_string(value):
    return '"' + "".join(f"\\x{byte:02x}" for byte in value.encode()) + '"'


archive = next(Path(os.environ["CHANNEL_DEPS"]).glob("tributary-*.tar.gz"))
with tarfile.open(archive) as dependency:
    source = next(
        item for item in dependency if item.name.endswith("/src/globbing.zig")
    )
    Path("globbing.zig").write_bytes(dependency.extractfile(source).read())

patterns = ",".join(zig_string(p) for p in json.loads(os.environ["TOUCHPAD_PATTERNS"]))
Path("device-matching.zig").write_text(
    'const testing = @import("std").testing;\n'
    'const matcher = @import("globbing.zig");\n'
    'test "native touchpad profiles match laptop and leave mouse wheels alone" {\n'
    f"const patterns = [_][]const u8 {{{patterns}}};\n"
    "for ([_][]const u8 {"
    + ",".join(
        zig_string(name)
        for name in (
            "PIXA3854:00 093A:0274 Touchpad",
            "ELAN1200 Touchpad",
            "Touchpad",
            "ELAN touchpad device",
        )
    )
    + "}) |name| {\n"
    " var found = false;\n"
    " for (patterns) |pattern| found = found or matcher.match(pattern, name);\n"
    " try testing.expect(found);\n"
    "}\n"
    'for ([_][]const u8 {"PIXA3854:00 093A:0274 Mouse", "USB Mouse"}) |name| {\n'
    " for (patterns) |pattern| try testing.expect(!matcher.match(pattern, name));\n"
    "}\n"
    "// The original contains-style glob silently missed this laptop.\n"
    'try testing.expect(!matcher.match("*Touchpad*", "PIXA3854:00 093A:0274 Touchpad"));\n'
    "}\n"
)
subprocess.run(["zig", "test", "device-matching.zig"], check=True)
