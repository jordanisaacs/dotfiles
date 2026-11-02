"""Convenience commands over the standard Nix and Home Manager CLIs."""

import argparse
import getpass
import json
import os
import shutil
import socket
import subprocess
import sys
from pathlib import Path


def run(arguments, **kwargs):
    return subprocess.run(arguments, check=True, **kwargs)


def capture(arguments, **kwargs):
    return run(arguments, text=True, capture_output=True, **kwargs).stdout.strip()


def store_path(command):
    executable = shutil.which(command)
    if executable is None:
        raise ValueError(f"Command not found: {command}")
    path = str(Path(executable).resolve())
    if not path.startswith("/nix/store/"):
        raise ValueError(f"Command is not in the Nix store: {path}")
    return "/".join(path.split("/")[:4])


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--flake-dir", type=Path, default=Path.home() / ".dotfiles")
    commands = result.add_subparsers(dest="command", required=True)
    for name in ["clean", "update", "update-index", "save", "apply-user", "installed"]:
        commands.add_parser(name)
    find = commands.add_parser("find")
    find.add_argument("pattern")
    catalogs = find.add_mutually_exclusive_group()
    catalogs.add_argument("--jd", action="store_true")
    catalogs.add_argument("--dot", action="store_true")
    for name in ["find-doc", "find-cmd", "depends", "which"]:
        commands.add_parser(name).add_argument("target")
    apply = commands.add_parser("apply")
    actions = apply.add_mutually_exclusive_group()
    for flag in ["boot", "test", "check"]:
        actions.add_argument(f"--{flag}", action="store_true")
    commands.add_parser("exec").add_argument("arguments", nargs=argparse.REMAINDER)
    return result


def main():
    args = parser().parse_args()
    if os.environ.get("INNIXSHELLHOME"):
        raise ValueError("sys cannot run from a Nix shell that redirects HOME")
    directory = args.flake_dir.expanduser().resolve()
    nix = CONFIG["nix"]
    nix_store = CONFIG["nixStore"]
    command = args.command
    if command == "clean":
        run([nix, "store", "gc"])
        run([nix, "store", "optimise"])
    elif command == "update":
        run([nix, "flake", "update"], cwd=directory)
    elif command == "update-index":
        run(["nix-index"])
    elif command == "save":
        for git_arguments in [
            ["diff"],
            ["add", "."],
            ["commit"],
            ["pull", "--rebase"],
            ["push"],
        ]:
            run(["git", *git_arguments], cwd=directory)
    elif command == "find":
        catalog = (
            "github:jordanisaacs/jdpkgs"
            if args.jd
            else str(directory)
            if args.dot
            else "nixpkgs"
        )
        run([nix, "search", catalog, args.pattern])
    elif command == "find-doc":
        run([CONFIG["manix"], args.target])
    elif command == "find-cmd":
        run(
            [
                "nix-locate",
                "--whole-name",
                "--type",
                "x",
                "--type",
                "s",
                "--no-group",
                "--top-level",
                "--at-root",
                f"/bin/{args.target}",
            ]
        )
    elif command == "apply":
        action = (
            "boot"
            if args.boot
            else "test"
            if args.test
            else "dry-activate"
            if args.check
            else "switch"
        )
        prefix = [] if args.check else ["sudo"]
        run([*prefix, CONFIG["nixosRebuild"], action, "--flake", str(directory) + "#"])
    elif command == "apply-user":
        target = f"{directory}#{getpass.getuser()}@{socket.gethostname()}"
        run([CONFIG["homeManager"], "switch", "--flake", target])
    elif command == "installed":
        paths = capture([nix_store, "-qR", "/run/current-system"]).splitlines()
        print("\n".join(sorted({Path(path).name[33:] for path in paths})))
    elif command == "depends":
        run([nix_store, "-qR", store_path(args.target)])
    elif command == "which":
        data = json.loads(capture([nix, "derivation", "show", store_path(args.target)]))
        derivations = data.get("derivations", data)
        for derivation in derivations.values():
            for output in derivation.get("outputs", {}).values():
                if output.get("path"):
                    print(output["path"])
    elif command == "exec":
        arguments = args.arguments
        if arguments and arguments[0] == "--":
            arguments = arguments[1:]
        if not arguments:
            raise ValueError("sys exec requires a command")
        candidates = capture(
            [
                "nix-locate",
                "--minimal",
                "--no-group",
                "--type",
                "x",
                "--type",
                "s",
                "--top-level",
                "--whole-name",
                "--at-root",
                f"/bin/{arguments[0]}",
            ]
        ).splitlines()
        if not candidates:
            raise ValueError(f"Package not found for {arguments[0]}")
        selected = candidates[0]
        if len(candidates) > 1:
            for number, candidate in enumerate(candidates, 1):
                print(f"{number}: {candidate}")
            number = int(input("Select package: "))
            if not 1 <= number <= len(candidates):
                raise ValueError("Invalid package selection")
            selected = candidates[number - 1]
        output = capture(
            [nix, "build", "--no-link", "--print-out-paths", f"nixpkgs#{selected}"]
        )
        executable = str(Path(output) / "bin" / arguments[0])
        os.execv(executable, [executable, *arguments[1:]])


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        print(f"sys: {error}", file=sys.stderr)
        raise SystemExit(getattr(error, "returncode", 1)) from error
