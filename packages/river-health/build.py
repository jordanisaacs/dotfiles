"""Build a native Wayland client against explicit pinned protocol inputs."""

import argparse
import os
import shlex
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name")
    parser.add_argument("source", type=Path)
    parser.add_argument("protocol", nargs="+", help="header-prefix=protocol.xml")
    args = parser.parse_args()
    protocols = []
    for definition in args.protocol:
        name, path = definition.split("=", 1)
        protocols.append(f"{name}-protocol.c")
        for mode, output in [
            ("client-header", f"{name}-client.h"),
            ("private-code", f"{name}-protocol.c"),
        ]:
            subprocess.run(["wayland-scanner", mode, path, output], check=True)
    flags = subprocess.check_output(
        ["pkg-config", "--cflags", "--libs", "wayland-client"], text=True
    )
    subprocess.run(
        [
            *shlex.split(os.environ["CC"]),
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-I.",
            str(args.source),
            *protocols,
            *shlex.split(flags),
            "-o",
            args.name,
        ],
        check=True,
    )
    destination = Path(os.environ["out"]) / "bin" / args.name
    destination.parent.mkdir(parents=True)
    destination.write_bytes(Path(args.name).read_bytes())
    destination.chmod(0o755)


if __name__ == "__main__":
    main()
