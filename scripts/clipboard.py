"""Search, copy and remove native clipboard history without a command shell."""

import argparse
import os
import resource
import subprocess
from pathlib import Path


def database() -> Path:
    if CONFIG["persistent"]:
        return Path(os.environ["XDG_RUNTIME_DIR"]) / "clipboard-history/plain/db"
    return Path(os.environ["XDG_RUNTIME_DIR"]) / "clipboard-history/db"


def history(command: str, *, data: bytes | None = None) -> bytes:
    return subprocess.run(
        [CONFIG["cliphist"], "-db-path", str(database()), command],
        input=data,
        check=True,
        capture_output=True,
    ).stdout


def choose(rows: list[str], prompt: str) -> tuple[int, int | None]:
    result = subprocess.run(
        [
            CONFIG["fuzzel"],
            "--dmenu",
            "--index",
            "--only-match",
            "--no-sort",
            "--counter",
            "--prompt",
            prompt,
            "--override",
            "key-bindings.custom-1=Shift+Delete",
            "--override",
            "key-bindings.custom-2=Control+Shift+Delete",
        ],
        check=False,
        input="\n".join(rows) + "\n",
        text=True,
        capture_output=True,
    )
    if result.returncode not in (0, 1, 2, 10, 11):
        result.check_returncode()
    selected = result.stdout.strip()
    return result.returncode, int(selected) if selected.isdecimal() else None


def clear() -> None:
    code, selected = choose(
        ["Cancel", "Clear saved clipboard history"], "Clear history: "
    )
    if code == 0 and selected == 1:
        history("wipe")


def entries() -> list[tuple[bytes, str]]:
    if not database().exists():
        return []
    result = []
    for line in history("list").splitlines():
        identifier, separator, preview = line.partition(b"\t")
        if separator and identifier.isdigit():
            text = "".join(
                character
                for character in preview.decode(errors="replace")
                if character.isprintable()
            )
            result.append((identifier, text))
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "action", choices=("pick", "delete", "clear"), default="pick", nargs="?"
    )
    arguments = parser.parse_args()
    os.umask(0o077)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    os.environ["TMPDIR"] = os.environ["XDG_RUNTIME_DIR"]
    if CONFIG["persistent"]:
        mount = database().parent
        if not mount.is_mount():
            subprocess.run([CONFIG["vault"], "unlock"], check=True)
        if not mount.is_mount():
            raise RuntimeError("The encrypted clipboard vault is not mounted")
    if arguments.action == "clear":
        clear()
        return
    while True:
        values = entries()
        if not values:
            choose(["No saved clipboard entries"], "Clipboard: ")
            return
        prompt = "Delete entry: " if arguments.action == "delete" else "Clipboard: "
        code, selected = choose([text for _, text in values], prompt)
        if code in (1, 2):
            return
        if code == 11:
            clear()
            continue
        if selected is None or not 0 <= selected < len(values):
            return
        identifier = values[selected][0] + b"\t\n"
        if code == 10 or arguments.action == "delete":
            history("delete", data=identifier)
            if arguments.action == "delete":
                return
            continue
        if code == 0:
            content = history("decode", data=identifier)
            # Native wl-copy infers the MIME type from the decoded bytes. This
            # retains images as images rather than replacing them with previews.
            subprocess.run([CONFIG["wlCopy"]], input=content, check=True)
            return


if __name__ == "__main__":
    main()
