"""Switch River's window manager while retaining the compositor and its apps."""

import argparse
import fcntl
import os
import subprocess
import sys
from pathlib import Path


def systemctl(*arguments, check=True):
    return subprocess.run(
        [CONFIG["systemctl"], "--user", *arguments],
        check=check,
        capture_output=True,
        text=True,
    )


def active(unit):
    result = systemctl("is-active", "--quiet", unit, check=False)
    if result.returncode not in (0, 3, 4):
        raise RuntimeError(result.stderr.strip() or f"Could not query {unit}")
    return result.returncode == 0


def current_manager():
    managers = [
        name for name in ("reka", "oxbow") if active(f"river-wm-{name}.service")
    ]
    if len(managers) > 1:
        raise RuntimeError(
            "Both window managers are active; inspect their user services"
        )
    return managers[0] if managers else None


def import_compositor_environment():
    names = [
        name
        for name in (
            "WAYLAND_DISPLAY",
            "DISPLAY",
            "XCURSOR_THEME",
            "XCURSOR_SIZE",
            "XDG_CURRENT_DESKTOP",
            "XDG_SESSION_DESKTOP",
            "XDG_SESSION_TYPE",
            "XDG_CONFIG_HOME",
            "XDG_CACHE_HOME",
            "XDG_DATA_HOME",
            "XDG_STATE_HOME",
            "XDG_DATA_DIRS",
            "PATH",
        )
        if name in os.environ
    ]
    if not os.environ.get("WAYLAND_DISPLAY"):
        raise RuntimeError("River did not provide a Wayland display")
    systemctl("import-environment", *names)
    # These belong to a previous WM, never to the compositor's initial state.
    systemctl("unset-environment", "OXBOW_SOCKET", "JD_RIVER_WM", "JD_DESKTOP_READY")


def switch_manager(manager, *, initialize=False):
    previous = current_manager()
    if initialize:
        import_compositor_environment()
    elif previous is None:
        raise RuntimeError(
            "This login uses an unmanaged window manager. Log out and back in once "
            "to start the patched River and managed services before switching."
        )
    elif not active("graphical-session.target"):
        raise RuntimeError(
            "The graphical session is still starting; try again once it is ready"
        )
    if manager == "toggle":
        manager = "oxbow" if previous == "reka" else "reka"
    if previous == manager:
        print(manager)
        return
    target = f"river-wm-{manager}.service"
    if previous:
        systemctl("stop", f"river-wm-{previous}.service")
    try:
        # Type=notify makes this wait for native WM readiness, not just exec().
        systemctl("start", target)
    except subprocess.CalledProcessError as error:
        # Cancel a pending on-failure restart before restoring the old manager.
        systemctl("stop", target, check=False)
        if previous:
            systemctl("start", f"river-wm-{previous}.service")
        detail = error.stderr.strip() or str(error)
        raise RuntimeError(
            f"Could not start {manager}: {detail}. "
            f"Inspect journalctl --user -b -u {target}."
        ) from error
    if not initialize and active("waybar.service"):
        systemctl("try-restart", "waybar.service")
    print(manager)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manager", choices=("reka", "oxbow", "toggle", "status"))
    parser.add_argument("--initialize", action="store_true", help=argparse.SUPPRESS)
    arguments = parser.parse_args()
    if arguments.manager == "status":
        print(current_manager() or "unmanaged")
        return
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise RuntimeError("XDG_RUNTIME_DIR is not set; run this in your user session")
    descriptor = os.open(Path(runtime) / "river-wm.lock", os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(descriptor, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        switch_manager(arguments.manager, initialize=arguments.initialize)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error
