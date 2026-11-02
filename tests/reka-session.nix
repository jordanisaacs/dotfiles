{
  pkgs,
  homeConfiguration,
  withPipes ? true,
}:
let
  home = homeConfiguration.config;
  username = home.home.username;
  homeDirectory = home.home.homeDirectory;
  runtime = "/run/user/1000";
  session = home.home.file.".winitrc".source;
  rekaInit =
    if withPipes then
      home.xdg.configFile."reka/init.el".source
    else
      pkgs.writeText "reka-init-with-pty.el" (
        # Negative control restores Emacs' PTY launch path in the real session.
        pkgs.lib.replaceStrings [ "(process-connection-type nil)" ] [ "(process-connection-type t)" ]
          home.xdg.configFile."reka/init.el".text
      );
  kanshiUnit = home.xdg.configFile."systemd/user/kanshi.service".source;
  inputUnit = home.xdg.configFile."systemd/user/river-input.service".source;
  switcher = "${home.jd.graphical.wayland.river.switchPackage}/bin/river-wm";
  brokenManager = pkgs.writeText "reka-test-broken-manager.conf" ''
    [Service]
    ExecStart=
    ExecStart=${pkgs.coreutils}/bin/false
    Restart=no
  '';
  kanshiFixture =
    pkgs.runCommand "reka-headless-display-policy"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        KANSHI_SOURCE = home.xdg.configFile."kanshi/config".source;
        INTERNAL_OUTPUT = home.jd.graphical.wayland.display.internalOutput;
      }
      ''
        python -B ${./prepare_display_fixture.py}
      '';
  application = pkgs.writers.writePython3Bin "reka-session-application" { } ''
    import json
    import os
    from pathlib import Path

    # A daemonizing graphical launcher exercises UWSM's cgroup lifetime, then
    # becomes a real Wayland client whose received keys can be inspected.
    if os.fork():
        raise SystemExit(0)
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    (runtime / "reka-session-app.json").write_text(json.dumps({
        "pid": os.getpid(),
        "cgroup": Path("/proc/self/cgroup").read_text(),
        "environment": {
            name: os.environ.get(name) for name in (
                "WAYLAND_DISPLAY", "DISPLAY", "JD_DESKTOP_READY",
                "XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP", "XDG_DATA_DIRS",
                "TMUX_TMPDIR", "SUDO_ASKPASS",
            )
        },
    }))
    log = os.open(runtime / "reka-session-keys.log",
                  os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.dup2(log, 1)
    os.dup2(log, 2)
    os.close(log)
    executable = (
        "${pkgs.coreutils}"
        "/bin/stdbuf"
    )
    os.execv(executable, [
        executable,
        "-oL",
        "-eL",
        "${pkgs.wev}/bin/wev",
    ])
  '';
  profile = pkgs.buildEnv {
    name = "reka-session-test-profile";
    paths = [
      home.home.pointerCursor.package
      home.jd.graphical.wayland.river.switchPackage
      (pkgs.writeTextDir "share/applications/reka-session-regression.desktop" ''
        [Desktop Entry]
        Type=Application
        Name=Reka Session Regression Fixture
        Exec=${application}/bin/reka-session-application
        Terminal=false
      '')
    ];
  };
  headlessXwayland = pkgs.writers.writePython3Bin "reka-headless-xwayland" { } ''
    import os
    import sys

    executable = (
        "${pkgs.xwayland}"
        "/bin/Xwayland"
    )
    os.execv(executable, [executable, "-glamor", "off", *sys.argv[1:]])
  '';
  login = pkgs.writers.writePython3Bin "reka-test-login" { } ''
    import os

    xwayland = (
        "${headlessXwayland}"
        "/bin/reka-headless-xwayland"
    )
    os.environ.update({
        "WLR_BACKENDS": "headless",
        "WLR_RENDERER": "pixman",
        "WLR_HEADLESS_OUTPUTS": "2",
        "WLR_XWAYLAND": xwayland,
        "XDG_DATA_DIRS": "/run/current-system/sw/share",
    })
    executable = (
        "${builtins.dirOf session}"
        "/${builtins.baseNameOf session}"
    )
    # The fixture selects Reka for this login while the tested Home Manager
    # configuration keeps Oxbow as its declarative default.
    os.execv(executable, [executable, "--window-manager", "reka"])
  '';
in
pkgs.testers.runNixOSTest {
  name = "river-reka-systemd-session";
  nodes.machine = {
    virtualisation = {
      memorySize = 2048;
      cores = 2;
    };
    programs.uwsm.enable = true;
    fonts.packages = [
      pkgs.noto-fonts
      pkgs.dejavu_fonts
    ];
    users.users.${username} = {
      isNormalUser = true;
      uid = 1000;
      home = homeDirectory;
      linger = true;
    };
    systemd.tmpfiles.rules = [
      "d ${homeDirectory}/.config 0755 ${username} users -"
      "d ${homeDirectory}/.config/river 0755 ${username} users -"
      "d ${homeDirectory}/.config/oxbow 0755 ${username} users -"
      "d ${homeDirectory}/.config/reka 0755 ${username} users -"
      "d ${homeDirectory}/.config/kanshi 0755 ${username} users -"
      "d ${homeDirectory}/.config/fuzzel 0755 ${username} users -"
      "L+ ${homeDirectory}/.config/fuzzel/fuzzel.ini - - - - ${
        home.xdg.configFile."fuzzel/fuzzel.ini".source
      }"
      "d ${homeDirectory}/.config/systemd 0755 ${username} users -"
      "d ${homeDirectory}/.config/systemd/user 0755 ${username} users -"
      "d ${homeDirectory}/.config/systemd/user/graphical-session.target.wants 0755 ${username} users -"
      "d ${homeDirectory}/.config/systemd/user/wayland-wm@river.service.d 0755 ${username} users -"
      "L+ ${homeDirectory}/.config/systemd/user/wayland-wm@river.service.d/50-window-managers.conf - - - - ${
        home.xdg.configFile."systemd/user/wayland-wm@river.service.d/50-window-managers.conf".source
      }"
      "L+ ${homeDirectory}/.winitrc - - - - ${session}"
      "L+ ${homeDirectory}/.config/river/init - - - - ${home.xdg.configFile."river/init".source}"
      "L+ ${homeDirectory}/.config/river/config.rh - - - - ${
        home.xdg.configFile."river/config.rh".source
      }"
      "L+ ${homeDirectory}/.config/reka/init.el - - - - ${rekaInit}"
      "L+ ${homeDirectory}/.config/oxbow/init - - - - ${home.xdg.configFile."oxbow/init".source}"
      "L+ ${homeDirectory}/.config/kanshi/config - - - - ${kanshiFixture}"
      "L+ ${homeDirectory}/.config/systemd/user/kanshi.service - - - - ${kanshiUnit}"
      "L+ ${homeDirectory}/.config/systemd/user/graphical-session.target.wants/kanshi.service - - - - ${kanshiUnit}"
      "L+ ${homeDirectory}/.config/systemd/user/river-input.service - - - - ${inputUnit}"
      "L+ ${homeDirectory}/.config/systemd/user/river-wm-reka.service - - - - ${
        home.xdg.configFile."systemd/user/river-wm-reka.service".source
      }"
      "L+ ${homeDirectory}/.config/systemd/user/river-wm-oxbow.service - - - - ${
        home.xdg.configFile."systemd/user/river-wm-oxbow.service".source
      }"
      "L+ ${home.home.profileDirectory} - - - - ${profile}"
    ];
    services = {
      dbus.implementation = "broker";
      greetd = {
        enable = true;
        settings = {
          initial_session = {
            user = username;
            command = "${login}/bin/reka-test-login";
          };
          default_session.command = "${pkgs.coreutils}/bin/sleep infinity";
        };
      };
    };
  };
  testScript = ''
    from datetime import timedelta
    import json
    import re
    import shlex

    runtime = "${runtime}"

    def user(*arguments):
        return shlex.join([
            "runuser", "-u", "${username}", "--", "env",
            "XDG_RUNTIME_DIR=" + runtime,
            "DBUS_SESSION_BUS_ADDRESS=unix:path=" + runtime + "/bus",
            *arguments,
        ])

    def manager_environment():
        return dict(
            line.split("=", 1) for line in machine.succeed(
                user("systemctl", "--user", "show-environment")
            ).splitlines() if "=" in line
        )

    def evaluate(form):
        return machine.succeed(user(
            "${pkgs.reka-emacs}/bin/emacsclient", "--socket-name", "reka",
            "--alternate-editor", "${pkgs.coreutils}/bin/false", "--eval", form,
        )).strip()

    def unit_properties(unit):
        return dict(line.split("=", 1) for line in machine.succeed(user(
            "systemctl", "--user", "show", unit,
            "--property=Type,MainPID,ControlGroup,Slice,InvocationID,Result,ExecMainStatus",
        )).splitlines())

    start_all()
    machine.wait_for_unit("greetd.service")
    try:
        machine.wait_until_succeeds(
            user("systemctl", "--user", "is-active", "graphical-session.target"),
            timeout=timedelta(minutes=3),
        )
        machine.wait_until_succeeds(user("test", "-S", runtime + "/emacs/reka"))
    except Exception:
        print(machine.succeed("journalctl -b --no-pager _UID=1000"))
        raise
    environment = manager_environment()
    assert environment["JD_DESKTOP_READY"] == "1", environment
    assert environment["XDG_CURRENT_DESKTOP"] == "river", environment
    assert environment["XDG_SESSION_TYPE"] == "wayland", environment
    assert environment["WAYLAND_DISPLAY"] and environment["DISPLAY"], environment
    assert "OXBOW_SOCKET" not in environment, environment
    assert environment["JD_RIVER_WM"] == "reka", environment
    assert evaluate("reka-ready") == "t"
    controller_pid = int(evaluate("(emacs-pid)"))
    river_pid = int(machine.succeed(user("pgrep", "--exact", "river")))
    controller = unit_properties("river-wm-reka.service")
    assert controller["Type"] == "notify", controller
    assert controller["Slice"] == "session.slice", controller
    assert int(controller["MainPID"]) == controller_pid, controller
    assert controller["ControlGroup"].endswith("/river-wm-reka.service"), controller
    assert machine.succeed(user("${switcher}", "status")).strip() == "reka"
    assert evaluate("(and reka-handle (reka-virtual-keyboard-available-p reka-handle))") == "t"
    machine.fail(user("pgrep", "--exact", "oxbow"))
    machine.wait_until_succeeds(user("systemctl", "--user", "is-active", "kanshi.service"))
    machine.wait_until_succeeds(user("systemctl", "--user", "is-active", "river-input.service"))
    for attempt in range(30):
        outputs = json.loads(machine.succeed(user(
            "env", "WAYLAND_DISPLAY=" + environment["WAYLAND_DISPLAY"],
            "${pkgs.wlr-randr}/bin/wlr-randr", "--json",
        )))
        scales = {output["name"]: output["scale"] for output in outputs}
        if scales.get("HEADLESS-1") == ${toString home.jd.graphical.wayland.display.internalScale}:
            break
        machine.sleep(duration=timedelta(seconds=1))
    else:
        raise AssertionError(scales)
    assert scales["HEADLESS-2"] == 1.0, scales
    assert environment["TMUX_TMPDIR"] == runtime, environment
    data_dirs = environment["XDG_DATA_DIRS"].split(":")
    assert "${home.home.profileDirectory}/share" in data_dirs, data_dirs
    assert "/run/current-system/sw/share" in data_dirs, data_dirs
    assert all(path.startswith("/") and "$" not in path for path in data_dirs), data_dirs
    machine.succeed(user("test", "-x", environment["SUDO_ASKPASS"]))
    wayland = "WAYLAND_DISPLAY=" + environment["WAYLAND_DISPLAY"]
    # Give the private headless seat the keyboard capability a real laptop has.
    machine.succeed(user(
        "systemd-run", "--user", "--unit=reka-test-keyboard", "--collect",
        "--setenv=" + wayland, "${pkgs.wtype}/bin/wtype", "-k", "F35", "-s", "300000",
    ))
    # Invoke the desktop's configured launcher binding, not a test-owned
    # service: Emacs must launch through pipes so exiting Fuzzel cannot HUP
    # its asynchronous UWSM child before the application service starts.
    machine.succeed(user(
        "env", wayland, "${pkgs.wtype}/bin/wtype",
        "-M", "logo", "-k", "${if home.jd.keybindings == "emacs" then "x" else "p"}", "-m", "logo",
    ))
    machine.wait_until_succeeds(user("pgrep", "--exact", "fuzzel"))
    machine.succeed(user(
        "env", wayland, "${pkgs.wtype}/bin/wtype", "-s", "300",
        "Reka Session Regression Fixture", "-k", "Return",
    ))
    machine.wait_for_file(runtime + "/reka-session-app.json", timeout=timedelta(seconds=30))
    state = json.loads(machine.succeed("cat " + runtime + "/reka-session-app.json"))
    app_unit = state["cgroup"].strip().rsplit("/", 1)[1]
    machine.succeed(user("systemctl", "--user", "is-active", app_unit))
    properties = machine.succeed(user(
        "systemctl", "--user", "show", app_unit,
        "--property=Slice", "--property=ExitType",
    ))
    assert "Slice=app-graphical.slice" in properties, properties
    assert "ExitType=cgroup" in properties, properties
    assert "/app-graphical.slice/" in state["cgroup"], state
    for name, value in state["environment"].items():
        assert value == environment[name], (name, value, environment[name])
    application_invocation = unit_properties(app_unit)["InvocationID"]
    buffers = "(append (reka--list-buffers) nil)"
    machine.wait_until_succeeds(user(
        "${pkgs.reka-emacs}/bin/emacsclient", "--socket-name", "reka", "--eval",
        '(unless (= 1 (length ' + buffers + ')) (error "Waiting for real client"))',
    ))
    assert evaluate('(with-current-buffer (car ' + buffers + ') (stringp reka-app-id))') == "t"
    # Do not select the buffer from the test: the first launched application
    # must already have a visible tile and keyboard focus without intervention.
    assert evaluate('(let ((buffer (car ' + buffers + '))) '
                    '(and (get-buffer-window buffer t) '
                    '(eq (window-buffer (selected-window)) buffer)))') == "t"
    offset = int(machine.succeed("stat --format=%s " + runtime + "/reka-session-keys.log"))
    machine.succeed(user("env", wayland, "${pkgs.wtype}/bin/wtype", "v"))
    output = machine.succeed("tail -c +" + str(offset + 1) + " " + runtime + "/reka-session-keys.log")
    assert re.search(r"sym: +v\b", output), output
    # The public desktop binding must toggle the real client twice while
    # retaining focus, rather than toggling an underlying tile on the return.
    def toggle_floating():
        machine.succeed(user(
            "env", wayland, "${pkgs.wtype}/bin/wtype",
            "-M", "logo", "-k", "space", "-m", "logo",
        ))

    toggle_floating()
    machine.wait_until_succeeds(user(
        "${pkgs.reka-emacs}/bin/emacsclient", "--socket-name", "reka", "--eval",
        '(unless (with-current-buffer (car ' + buffers + ') reka-floating) (error "Not floating"))',
    ))
    assert evaluate('(eq reka--focused-floating-buffer (car ' + buffers + '))') == "t"
    offset = int(machine.succeed("stat --format=%s " + runtime + "/reka-session-keys.log"))
    assert evaluate('(progn (require \'reka-simulation) (reka-send-keys "a C-b A RET 🙂 C-x") t)') == "t"
    machine.wait_until_succeeds("grep -q '🙂' " + runtime + "/reka-session-keys.log")
    output = machine.succeed("tail -c +" + str(offset + 1) + " " + runtime + "/reka-session-keys.log")
    events = re.findall(r"key: (\d+); state: (\d+)", output)
    assert len(events) == 12, output
    assert all(events[i][0] == events[i+1][0] and events[i][1] == "1" and events[i+1][1] == "0"
               for i in range(0, len(events), 2)), output
    assert "Control" in output and "Shift" in output and "Return" in output, output
    toggle_floating()
    machine.wait_until_succeeds(user(
        "${pkgs.reka-emacs}/bin/emacsclient", "--socket-name", "reka", "--eval",
        '(when (with-current-buffer (car ' + buffers + ') reka-floating) (error "Still floating"))',
    ))

    def assert_session_survives():
        assert int(machine.succeed(user("pgrep", "--exact", "river"))) == river_pid
        machine.succeed("kill -0 " + str(state["pid"]))
        machine.succeed(user("systemctl", "--user", "is-active", app_unit))
        assert unit_properties(app_unit)["InvocationID"] == application_invocation
        machine.succeed(user("systemctl", "--user", "is-active", "graphical-session.target"))
        machine.succeed(user("systemctl", "--user", "is-active", "kanshi.service"))

    def assert_oxbow():
        assert_session_survives()
        assert machine.succeed(user("${switcher}", "status")).strip() == "oxbow"
        machine.succeed(user("systemctl", "--user", "is-active", "river-wm-oxbow.service"))
        machine.fail(user("systemctl", "--user", "is-active", "river-wm-reka.service"))
        machine.wait_until_fails(user("systemctl", "--user", "is-active", "river-input.service"))
        current = manager_environment()
        assert current["JD_RIVER_WM"] == "oxbow", current
        assert current["OXBOW_SOCKET"], current
        windows = json.loads(machine.succeed(user(
            "env", "OXBOW_SOCKET=" + current["OXBOW_SOCKET"],
            "${pkgs.oxbow}/bin/oxctl", "window", "list", "--json",
        )))
        assert windows and "wev" in json.dumps(windows), windows
        return current

    # Swap the native window manager while the compositor and the already
    # running graphical application's cgroup remain alive throughout.
    machine.succeed(user("${switcher}", "toggle"))
    oxbow_environment = assert_oxbow()
    machine.wait_until_fails("kill -0 " + str(controller_pid))
    retired_controller = unit_properties("river-wm-reka.service")
    assert retired_controller["Result"] == "success", retired_controller
    assert retired_controller["ExecMainStatus"] == "0", retired_controller
    machine.succeed(user(
        "env", "OXBOW_SOCKET=" + oxbow_environment["OXBOW_SOCKET"],
        "${pkgs.oxbow}/bin/oxctl", "window", "focus", "match", "--app-id", "^wev$",
    ))
    offset = int(machine.succeed("stat --format=%s " + runtime + "/reka-session-keys.log"))
    machine.succeed(user("env", wayland, "${pkgs.wtype}/bin/wtype", "o"))
    output = machine.succeed("tail -c +" + str(offset + 1) + " " + runtime + "/reka-session-keys.log")
    assert re.search(r"sym: +o\b", output), output

    # A bad candidate must restore the previous manager rather than ending the
    # session. This drop-in and every affected process belong only to the VM.
    dropin_directory = "${homeDirectory}/.config/systemd/user/river-wm-reka.service.d"
    dropin = dropin_directory + "/90-fixture-failure.conf"
    machine.succeed(user("mkdir", "-p", dropin_directory))
    machine.succeed(user("ln", "-s", "${brokenManager}", dropin))
    machine.succeed(user("systemctl", "--user", "daemon-reload"))
    machine.fail(user("${switcher}", "reka"))
    assert_oxbow()
    machine.succeed(user("rm", dropin))
    machine.succeed(user("systemctl", "--user", "daemon-reload"))
    machine.succeed(user("${switcher}", "toggle"))
    assert_session_survives()
    machine.wait_until_succeeds(user("systemctl", "--user", "is-active", "river-input.service"))
    machine.fail(user("systemctl", "--user", "is-active", "river-wm-oxbow.service"))
    environment = manager_environment()
    assert environment["JD_RIVER_WM"] == "reka", environment
    assert "OXBOW_SOCKET" not in environment, environment
    assert evaluate("reka-ready") == "t"
    replacement_pid = int(evaluate("(emacs-pid)"))
    assert replacement_pid != controller_pid, (replacement_pid, controller_pid)
    controller_pid = replacement_pid
    assert evaluate('(= 1 (length ' + buffers + '))') == "t"
    assert evaluate('(let ((buffer (car ' + buffers + '))) '
                    '(and (get-buffer-window buffer t) '
                    '(eq (window-buffer (selected-window)) buffer)))') == "t"
    offset = int(machine.succeed("stat --format=%s " + runtime + "/reka-session-keys.log"))
    assert evaluate('(with-current-buffer (car ' + buffers + ') (reka-send-keys "z") t)') == "t"
    output = machine.succeed("tail -c +" + str(offset + 1) + " " + runtime + "/reka-session-keys.log")
    assert re.search(r"sym: +z\b", output), output
    sessions = json.loads(machine.succeed("loginctl list-sessions --json=short"))
    login_sessions = [s["session"] for s in sessions
                      if s["user"] == "${username}" and s["class"] == "user"]
    assert len(login_sessions) == 1, sessions
    # Exercise the managed WM's actual logout binding, including session target
    # shutdown and removal of the inherited display environment.
    assert evaluate("(progn (run-at-time 0.2 nil (lambda () (call-interactively (key-binding (kbd \"s-S-q\"))))) t)") == "t"
    # The shared logout UI now waits for consent before asking real windows
    # to close. Inspect its native GTK action before confirming the request.
    logout_application = "dev.snowytrees.DesktopLogout"
    for attempt in range(100):
        status, action_state = machine.execute(user(
            "busctl", "--user", "call", logout_application,
            "/dev/snowytrees/DesktopLogout", "org.gtk.Actions", "Describe", "s", "confirm",
        ))
        if status == 0 and "true" in action_state:
            break
        machine.sleep(duration=timedelta(milliseconds=100))
    else:
        raise AssertionError(action_state)
    machine.succeed(user("systemctl", "--user", "is-active", "graphical-session.target", app_unit))
    machine.succeed("kill -0 " + str(controller_pid) + " " + str(state["pid"]))
    machine.succeed(user("${pkgs.glib.bin}/bin/gapplication", "action", logout_application, "confirm"))
    machine.wait_until_fails(user("systemctl", "--user", "is-active", "graphical-session.target"))
    machine.wait_until_fails(user("systemctl", "--user", "is-active", app_unit))
    machine.wait_until_fails(user("systemctl", "--user", "is-active", "kanshi.service"))
    machine.wait_until_fails(user("systemctl", "--user", "is-active", "river-input.service"))
    machine.wait_until_fails("kill -0 " + str(state["pid"]))
    machine.wait_until_fails(user("pgrep", "--exact", "river"))
    machine.wait_until_fails("kill -0 " + str(controller_pid))
    stopped_controller = unit_properties("river-wm-reka.service")
    if stopped_controller["Result"] != "success":
        print(machine.succeed("journalctl -b --no-pager _UID=1000"))
    assert stopped_controller["Result"] == "success", stopped_controller
    assert stopped_controller["ExecMainStatus"] == "0", stopped_controller
    # A forced termination may leave an already dead Unix socket. Prove the
    # controller and its server are gone rather than requiring file unlinking.
    machine.fail(user(
        "${pkgs.reka-emacs}/bin/emacsclient", "--socket-name", "reka",
        "--alternate-editor", "${pkgs.coreutils}/bin/false", "--eval", "t",
    ))
    for attempt in range(60):
        environment = manager_environment()
        if not {"WAYLAND_DISPLAY", "DISPLAY", "JD_DESKTOP_READY", "JD_RIVER_WM", "OXBOW_SOCKET"} & environment.keys():
            break
        machine.sleep(duration=timedelta(seconds=1))
    else:
        raise AssertionError(environment)
    machine.wait_until_fails("loginctl show-session " + login_sessions[0])
  '';
}
