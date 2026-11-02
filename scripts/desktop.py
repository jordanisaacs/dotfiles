"""Desktop entry points; package paths and preferences come from Nix."""

import argparse
import os
import subprocess
import sys


def run(arguments, **kwargs):
    return subprocess.run(arguments, check=True, **kwargs)


def execute_command():
    arguments = CONFIG["command"] + sys.argv[1:]
    os.environ.update(CONFIG.get("environment", {}))
    os.execv(arguments[0], arguments)


def session():
    parser = argparse.ArgumentParser(description="Start the configured Wayland session")
    parser.add_argument("--window-manager", choices=("oxbow", "reka"))
    arguments = parser.parse_args()
    is_river = CONFIG["environment"]["XDG_CURRENT_DESKTOP"] == "river"
    if arguments.window_manager and not is_river:
        parser.error("window-manager selection requires a River session")
    os.environ.pop("JD_RIVER_SESSION_WM", None)
    if arguments.window_manager:
        os.environ["JD_RIVER_SESSION_WM"] = arguments.window_manager
    for name, value in CONFIG["environment"].items():
        os.environ[name] = os.path.expandvars(str(value))
    # Home Manager's shell expressions are not Python variable expansions.
    # Keep both its schema paths and the login's application/portal search path.
    inherited_data = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    data_directories = CONFIG["dataDirectories"] + inherited_data.split(os.pathsep)
    os.environ["XDG_DATA_DIRS"] = os.pathsep.join(dict.fromkeys(data_directories))
    runtime_directory = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    for name in CONFIG["runtimeDirectoryVariables"]:
        os.environ[name] = runtime_directory
    profile_bin = CONFIG["profileBin"]
    os.environ["PATH"] = profile_bin + os.pathsep + os.environ.get("PATH", "")
    arguments = [CONFIG["uwsm"], "start", "-F", "--", *CONFIG["command"]]
    os.execv(arguments[0], arguments)


def setup():
    # River's managers have their own notify sockets and cgroups. They notify
    # their service here; river/init finalizes UWSM from the compositor cgroup.
    if os.environ.get("JD_RIVER_WM"):
        systemctl = CONFIG["systemctl"]
        names = [
            name
            for name in ("OXBOW_SOCKET", "XCURSOR_SIZE", "XCURSOR_THEME")
            if name in os.environ
        ]
        if names:
            run([systemctl, "--user", "import-environment", *names])
        if "OXBOW_SOCKET" not in os.environ:
            run([systemctl, "--user", "unset-environment", "OXBOW_SOCKET"])
        run(
            [
                systemctl,
                "--user",
                "set-environment",
                f"JD_RIVER_WM={os.environ['JD_RIVER_WM']}",
                "JD_DESKTOP_READY=1",
            ]
        )
        run([CONFIG["notify"], "--ready", "--status=Window manager ready"])
        return
    finalize_session()


def finalize_session():
    # This must run in River/Sway's original UWSM compositor service. A notify
    # call from a separate WM service cannot acknowledge that service's startup.
    run(
        [
            CONFIG["uwsm"],
            "finalize",
            "JD_DESKTOP_READY=1",
            "OXBOW_SOCKET",
            "SWAYSOCK",
            "I3SOCK",
            "XCURSOR_SIZE",
            "XCURSOR_THEME",
            "JD_RIVER_WM",
        ]
    )


def start_river_manager():
    manager = os.environ.pop("JD_RIVER_SESSION_WM", CONFIG["windowManager"])
    os.environ["JD_RIVER_WM"] = manager
    run([*CONFIG["command"], "--initialize", manager])
    finalize_session()


def exit_session():
    run([CONFIG["uwsm"], "stop"])


def capture():
    arguments = [CONFIG["grim"]]
    if CONFIG["mode"] == "display":
        output = run(
            [CONFIG["slurp"], "-o", "-f", "%o"], capture_output=True, text=True
        )
        arguments.extend(["-o", output.stdout.strip()])
    elif CONFIG["mode"] == "region":
        region = run([CONFIG["slurp"]], capture_output=True, text=True)
        arguments.extend(["-g", region.stdout.strip()])
    picture = run([*arguments, "-"], capture_output=True)
    run([CONFIG["wlCopy"], "--type", "image/png"], input=picture.stdout)


def toggle_service():
    parser = argparse.ArgumentParser(description="Toggle a user service")
    parser.add_argument("service")
    service = parser.parse_args().service
    systemctl = CONFIG["systemctl"]
    status = subprocess.run(
        [systemctl, "--user", "is-active", "--quiet", service], check=False
    )
    if status.returncode not in (0, 3):
        raise subprocess.CalledProcessError(status.returncode, status.args)
    run([systemctl, "--user", "stop" if status.returncode == 0 else "start", service])


def configure_oxbow():
    parser = argparse.ArgumentParser(description="Apply desktop preferences to Oxbow")
    parser.add_argument(
        "--configure-only",
        action="store_true",
        help="Reload bindings without restarting session services",
    )
    arguments = parser.parse_args()
    oxctl = CONFIG["oxctl"]

    def ox(*command):
        run([oxctl, *command])

    def bind(key, *command, mode=None):
        if mode is not None:
            command = (*command, "--mode", mode)
        ox("bind", *command, "to", key)

    def bind_exec(key, command):
        ox("bind", "exec", "--", *command, "to", key)

    if CONFIG["outerGap"] is not None:
        ox("gaps", "outer", "--all", str(CONFIG["outerGap"]))

    ox("input", "keyboard", "layout-file", CONFIG["keyboardKeymap"])
    ox(
        "input",
        "keyboard",
        "repeat",
        str(CONFIG["keyboardRepeatRate"]),
        str(CONFIG["keyboardRepeatDelay"]),
    )
    ox("input", "cursor", "theme", CONFIG["cursorTheme"], str(CONFIG["cursorSize"]))
    ox("input", "pointer", "follow", "always")
    ox(
        "input",
        "rules",
        "touchpad",
        "--name",
        ".*",
        "--tap",
        "enabled",
        "--tap-button-map",
        "left-right-middle",
        "--natural-scroll",
        "enabled",
        "--click-method",
        CONFIG["touchpadClickMethod"],
        "--clickfinger-button-map",
        "left-right-middle",
        "--scroll-factor",
        str(CONFIG["touchpadScrollFactor"]),
    )

    emacs = CONFIG["keybindings"] == "emacs"
    next_key, previous_key = ("n", "p") if emacs else ("j", "k")
    launcher = "x" if emacs else "p"
    smaller, larger = ("Control+b", "Control+f") if emacs else ("h", "l")
    more, fewer = ("Control+i", "Control+d") if emacs else ("i", "d")

    bind_exec(
        "Super+Shift+Return",
        [CONFIG["uwsm"], "app", "-t", "service", "--", CONFIG["terminal"]],
    )
    bind_exec(f"Super+{launcher}", [CONFIG["launcher"]])
    bind_exec("Super+Shift+q", [CONFIG["wayExit"]])
    # Oxbow's stock uppercase-Q binding exits immediately. Its key parser
    # folds letter names to lowercase, so use the exact XKB keysym to replace it.
    bind_exec("Super+0x51", [CONFIG["wayExit"]])
    bind("Super+Shift+c", "window", "close")
    bind(f"Super+{next_key}", "window", "focus", "next")
    bind(f"Super+{previous_key}", "window", "focus", "prev")
    bind(f"Super+Shift+{next_key}", "window", "shift", "next")
    bind(f"Super+Shift+{previous_key}", "window", "shift", "prev")
    for key, direction in [("period", "next"), ("comma", "prev")]:
        bind(f"Super+{key}", "output", "focus", direction)
        bind(f"Super+Shift+{key}", "window", "send", direction)
    bind("Super+Return", "window", "zoom")
    bind("Super+space", "window", "toggle", "floating")
    bind("Super+f", "window", "toggle", "fullscreen")
    bind("Super+Btn_left", "window", "move", "drag")
    bind("Super+Btn_right", "window", "resize", "drag")
    bind("Super+0", "tag", "view", "1-9")
    bind("Super+Shift+0", "window", "tag", "set", "1-9")
    for number in range(1, 10):
        tag = str(number)
        bind(f"Super+{tag}", "tag", "view", tag)
        bind(f"Super+Shift+{tag}", "window", "tag", "set", tag)
        bind(f"Super+Control+{tag}", "tag", "toggle", tag)
        bind(f"Super+Shift+Control+{tag}", "window", "toggle", "tag", tag)
    bind(f"Super+{smaller}", "layout", "tiling", "mfact", "-0.05")
    bind(f"Super+{larger}", "layout", "tiling", "mfact", "+0.05")
    bind(f"Super+{more}", "layout", "tiling", "nmaster", "+1")
    bind(f"Super+{fewer}", "layout", "tiling", "nmaster", "-1")
    bind("Super+m", "layout", "tiling", "monocle")
    bind("Super+t", "layout", "tiling", "even")
    for key in ["Up", "Left", "Down", "Right"]:
        bind(f"Super+{key}", "layout", "tiling", "orientation", key.lower())
    # A running, configured manager already owns its keymap modes. Reapplying
    # bindings must not redeclare them and abort before the hardware keys.
    if not arguments.configure_only:
        ox("keymap", "mode", "declare", "passthrough")
    bind("Super+F11", "keymap", "mode", "enter", "passthrough")
    bind("Super+F11", "keymap", "mode", "enter", "normal", mode="passthrough")

    for key, command in CONFIG["commandBindings"].items():
        bind_exec(key, command)
    if not arguments.configure_only:
        run([CONFIG["setup"]])


def main():
    actions = {
        "command": execute_command,
        "session": session,
        "setup": setup,
        "river-start": start_river_manager,
        "exit": exit_session,
        "capture": capture,
        "toggle": toggle_service,
        "oxbow": configure_oxbow,
    }
    try:
        actions[CONFIG["action"]]()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from error


if __name__ == "__main__":
    main()
