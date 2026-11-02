"""Start the authenticated account's Home Manager session or login shell."""

import argparse
import os
import pwd
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    session = parser.add_mutually_exclusive_group(required=True)
    session.add_argument("--window-manager", choices=("reka", "oxbow"))
    session.add_argument("--terminal", action="store_true")
    arguments = parser.parse_args()
    account = pwd.getpwuid(os.getuid())
    os.environ["HOME"] = account.pw_dir
    if arguments.terminal:
        os.environ.update(
            XDG_SESSION_TYPE="tty",
            XDG_SESSION_DESKTOP="terminal",
            DESKTOP_SESSION="terminal",
        )
        os.environ.pop("XDG_CURRENT_DESKTOP", None)
        os.execv(account.pw_shell, ["-" + Path(account.pw_shell).name])
    launcher = Path(account.pw_dir) / ".winitrc"
    if not launcher.is_file():
        parser.error(f"The Home Manager session is not installed at {launcher}")
    os.execv(
        str(launcher), [str(launcher), "--window-manager", arguments.window_manager]
    )


if __name__ == "__main__":
    main()
