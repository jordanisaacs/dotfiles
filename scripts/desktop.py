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
    wm = CONFIG["wmModifier"]
    mac = CONFIG["isMac"]
    normal_mode = "mac" if mac else None

    def ox(*command):
        run([oxctl, *command])

    def bind(key, *command, mode=None):
        mode = normal_mode if mode is None else mode
        if mode is not None:
            command = (*command, "--mode", mode)
        ox("bind", *command, "to", key)

    def bind_exec(key, command):
        mode = ("--mode", normal_mode) if normal_mode else ()
        ox("bind", "exec", *mode, "--", *command, "to", key)

    # A separate native mode keeps stock Super bindings inactive in Mac mode.
    # Configuration reloads reuse the modes already owned by this manager.
    if not arguments.configure_only:
        if mac:
            ox("keymap", "mode", "declare", normal_mode)
        ox("keymap", "mode", "declare", "passthrough")

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
    auxiliary = CONFIG["auxiliaryModifier"]
    next_key, previous_key = ("n", "p") if emacs else ("j", "k")
    launcher = "x" if emacs else "p"
    smaller, larger = (f"{auxiliary}+b", f"{auxiliary}+f") if emacs else ("h", "l")
    more, fewer = (f"{auxiliary}+i", f"{auxiliary}+d") if emacs else ("i", "d")

    bind_exec(
        f"{wm}+Shift+Return",
        [CONFIG["uwsm"], "app", "-t", "service", "--", CONFIG["terminal"]],
    )
    bind_exec(f"{wm}+{launcher}", [CONFIG["launcher"]])
    bind_exec(f"{wm}+Shift+q", [CONFIG["wayExit"]])
    if not mac:
        # Oxbow's stock uppercase-Q binding exits immediately. Its key parser
        # folds letter names to lowercase, so preserve the exact keysym.
        bind_exec("Super+0x51", [CONFIG["wayExit"]])
    else:
        bind_exec("Super+Shift+q", [CONFIG["wayExit"]])
        bind_exec("Super+space", [CONFIG["launcher"]])
        bind(CONFIG["nextWindow"], "window", "focus", "next")
        bind(CONFIG["previousWindow"], "window", "focus", "prev")
    bind(f"{wm}+Shift+c", "window", "close")
    bind(f"{wm}+{next_key}", "window", "focus", "next")
    bind(f"{wm}+{previous_key}", "window", "focus", "prev")
    bind(f"{wm}+Shift+{next_key}", "window", "shift", "next")
    bind(f"{wm}+Shift+{previous_key}", "window", "shift", "prev")
    for key, direction in [("period", "next"), ("comma", "prev")]:
        bind(f"{wm}+{key}", "output", "focus", direction)
        bind(f"{wm}+Shift+{key}", "window", "send", direction)
    bind(f"{wm}+Return", "window", "zoom")
    bind(f"{wm}+space", "window", "toggle", "floating")
    bind(CONFIG["fullscreen"], "window", "toggle", "fullscreen")
    bind(f"{wm}+Btn_left", "window", "move", "drag")
    bind(f"{wm}+Btn_right", "window", "resize", "drag")
    bind(f"{wm}+0", "tag", "view", "1-9")
    bind(f"{wm}+Shift+0", "window", "tag", "set", "1-9")
    for number in range(1, 10):
        tag = str(number)
        bind(f"{wm}+{tag}", "tag", "view", tag)
        bind(f"{wm}+Shift+{tag}", "window", "tag", "set", tag)
        bind(f"{wm}+{auxiliary}+{tag}", "tag", "toggle", tag)
        bind(f"{wm}+Shift+{auxiliary}+{tag}", "window", "toggle", "tag", tag)
    bind(f"{wm}+{smaller}", "layout", "tiling", "mfact", "-0.05")
    bind(f"{wm}+{larger}", "layout", "tiling", "mfact", "+0.05")
    bind(f"{wm}+{more}", "layout", "tiling", "nmaster", "+1")
    bind(f"{wm}+{fewer}", "layout", "tiling", "nmaster", "-1")
    bind(f"{wm}+m", "layout", "tiling", "monocle")
    bind(f"{wm}+t", "layout", "tiling", "even")
    for key in ["Up", "Left", "Down", "Right"]:
        bind(f"{wm}+{key}", "layout", "tiling", "orientation", key.lower())
    bind(f"{wm}+F11", "keymap", "mode", "enter", "passthrough")
    bind(
        f"{wm}+F11",
        "keymap",
        "mode",
        "enter",
        normal_mode or "normal",
        mode="passthrough",
    )

    for key, command in CONFIG["commandBindings"].items():
        bind_exec(key, command)
    if mac:
        ox("keymap", "mode", "enter", normal_mode)
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
