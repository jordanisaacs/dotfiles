"""Repair legacy SWT's hardcoded FHS MIME database in the bundled JAR."""

import struct
import sys
import zipfile
from pathlib import Path

plugins = Path(sys.argv[1])
database = Path(sys.argv[2])
assert database.is_file(), database
archives = list(plugins.glob("org.eclipse.swt.gtk.linux.x86_64_*.jar"))
assert len(archives) == 1, archives
archive = archives[0]
original = b"/usr/share/mime/globs"
replacement = str(database).encode()


def constant(value):
    # JVM CONSTANT_Utf8 records contain a tag, byte length and UTF-8 bytes.
    # Bytecode refers to constant-pool indexes, so changing a record's length
    # does not change indexes or offsets inside any method's bytecode.
    return b"\x01" + struct.pack(">H", len(value)) + value


temporary = archive.with_suffix(".patched")
replaced = False
with zipfile.ZipFile(archive) as source, zipfile.ZipFile(temporary, "w") as target:
    for entry in source.infolist():
        # Package-local code modifications invalidate the vendor JAR signature.
        # Nix still verifies the original distribution against its fixed hash.
        if entry.filename.startswith("META-INF/") and entry.filename.endswith(
            (".SF", ".RSA", ".DSA", ".EC")
        ):
            continue
        contents = source.read(entry)
        if entry.filename == "org/eclipse/swt/program/Program.class":
            assert contents.count(constant(original)) == 1, (
                "Bundled SWT changed; review whether this compatibility patch is still needed"
            )
            contents = contents.replace(constant(original), constant(replacement))
            replaced = True
        target.writestr(entry, contents)
assert replaced, "SWT Program.class was not found"
temporary.replace(archive)
