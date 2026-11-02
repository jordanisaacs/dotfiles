"""Run the same pinned formatting and lint checks locally and in Nix builds."""

import argparse
import subprocess
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("check", choices=["nixfmt", "statix", "deadnix", "ruff"])
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    source = arguments.source.resolve()
    tool = CONFIG[arguments.check]
    if arguments.check == "nixfmt":
        commands = [[tool, "--check", *map(str, sorted(source.rglob("*.nix")))]]
    elif arguments.check == "statix":
        commands = [[tool, "check", str(source)]]
    elif arguments.check == "deadnix":
        commands = [[tool, "--fail", str(source)]]
    else:
        commands = [
            [tool, "check", "--no-cache", str(source)],
            [tool, "format", "--check", "--no-cache", str(source)],
        ]
    for command in commands:
        subprocess.run(command, cwd=source, check=True)
    arguments.output.touch()


if __name__ == "__main__":
    main()
