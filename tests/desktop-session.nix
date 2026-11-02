{ pkgs, homeConfiguration }:
let
  home = homeConfiguration.config;
  username = home.home.username;
  homeDirectory = home.home.homeDirectory;
  session = home.home.file.".winitrc".source;
  riverInit = home.xdg.configFile."river/init".source;
  oxbowInit = home.xdg.configFile."oxbow/init".source;
  profile = pkgs.buildEnv {
    name = "desktop-test-profile";
    paths = [
      home.home.pointerCursor.package
      (pkgs.writeTextDir "share/applications/desktop-regression.desktop" ''
        [Desktop Entry]
        Type=Application
        Name=Desktop Regression Fixture
        Exec=${application}/bin/desktop-test-application
        Terminal=false
      '')
    ];
  };
  headlessXwayland = pkgs.writers.writePython3Bin "headless-xwayland" { } ''
    import os
    import sys

    executable = (
        "${pkgs.xwayland}"
        "/bin/Xwayland"
    )
    os.execv(executable, [executable, "-glamor", "off", *sys.argv[1:]])
  '';
  login = pkgs.writers.writePython3Bin "desktop-test-login" { flakeIgnore = [ "E501" ]; } ''
    import os

    os.environ.update({
        "WLR_BACKENDS": "headless",
        "WLR_RENDERER": "pixman",
        "WLR_HEADLESS_OUTPUTS": "1",
        # The fixture has no GPU; Xwayland should use its software path.
        "WLR_XWAYLAND": "${headlessXwayland}/bin/headless-xwayland",
        # Exercise Home Manager's path additions on top of a login environment.
        "XDG_DATA_DIRS": "/run/current-system/sw/share",
    })
    os.execv("${session}", ["${session}"])
  '';
  application = pkgs.writers.writePython3Bin "desktop-test-application" { } ''
    import json
    import os
    from pathlib import Path
    import signal

    # A real daemonizing application: its launcher exits while its child stays.
    # The service must follow the cgroup rather than just the initial PID.
    if os.fork():
        raise SystemExit(0)
    state = {
        "pid": os.getpid(),
        "cgroup": Path("/proc/self/cgroup").read_text(),
        "environment": {
            name: os.environ.get(name)
            for name in (
                "WAYLAND_DISPLAY", "DISPLAY", "OXBOW_SOCKET", "JD_DESKTOP_READY",
                "XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP",
                "XDG_DATA_DIRS", "TMUX_TMPDIR", "SUDO_ASKPASS",
            )
        },
    }
    path = Path(os.environ["XDG_RUNTIME_DIR"]) / "desktop-test-app.json"
    path.write_text(json.dumps(state))
    signal.pause()
  '';
in
pkgs.testers.runNixOSTest {
  name = "river-oxbow-systemd-session";

  nodes.machine = {
    virtualisation = {
      memorySize = 1536;
      cores = 2;
    };
    programs.uwsm.enable = true;
    services.dbus.implementation = "broker";
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
      "L+ ${homeDirectory}/.winitrc - - - - ${session}"
      "L+ ${homeDirectory}/.config/river/init - - - - ${riverInit}"
      "L+ ${homeDirectory}/.config/oxbow/init - - - - ${oxbowInit}"
      "L+ ${home.home.profileDirectory} - - - - ${profile}"
    ];
    services.greetd = {
      enable = true;
      settings = {
        initial_session = {
          user = username;
          command = "${login}/bin/desktop-test-login";
        };
        # After logout, keep the greeter alive without starting another session.
        default_session.command = "${pkgs.coreutils}/bin/sleep infinity";
      };
    };
  };

  testScript = ''
    import ast
    from datetime import timedelta
    import json
    from pathlib import Path
    import shlex

    runtime = "/run/user/1000"

    def user(*arguments):
        return shlex.join([
            "runuser", "-u", "${username}", "--", "env",
            "XDG_RUNTIME_DIR=" + runtime,
            "DBUS_SESSION_BUS_ADDRESS=unix:path=" + runtime + "/bus",
            *arguments,
        ])

    def manager_environment():
        return dict(
            line.split("=", 1)
            for line in machine.succeed(
                user("systemctl", "--user", "show-environment")
            ).splitlines()
            if "=" in line
        )

    start_all()
    machine.wait_for_unit("greetd.service")
    try:
        machine.wait_until_succeeds(
            user("systemctl", "--user", "is-active", "graphical-session.target"),
            timeout=timedelta(minutes=3),
        )
    except Exception:
        print(machine.succeed("journalctl -b --no-pager _UID=1000"))
        raise
    environment = manager_environment()
    assert environment["JD_DESKTOP_READY"] == "1", environment
    assert environment["XDG_SESSION_TYPE"] == "wayland", environment
    assert environment["XDG_CURRENT_DESKTOP"] == "river", environment
    assert environment["WAYLAND_DISPLAY"], environment
    assert environment["DISPLAY"], environment
    assert environment["OXBOW_SOCKET"], environment
    assert environment["TMUX_TMPDIR"] == runtime, environment["TMUX_TMPDIR"]
    data_dirs = environment["XDG_DATA_DIRS"].split(":")
    assert "/run/current-system/sw/share" in data_dirs, data_dirs
    assert "${home.home.profileDirectory}/share" in data_dirs, data_dirs
    assert all(directory.startswith("/") and "$" not in directory for directory in data_dirs), data_dirs
    for directory in ${builtins.toJSON home.xdg.systemDirs.data}:
        assert directory in data_dirs, data_dirs
    machine.succeed("test -x " + shlex.quote(environment["SUDO_ASKPASS"]))
    x11_environment = [
        name + "=" + environment[name]
        for name in ("DISPLAY", "XAUTHORITY") if name in environment
    ]
    machine.wait_until_succeeds(
        user("env", *x11_environment, "${pkgs.xdpyinfo}/bin/xdpyinfo"),
        timeout=timedelta(seconds=30),
    )
    journal = machine.succeed("journalctl -b -u user@1000.service --no-pager")
    for message in (
        "Eavesdropping is deprecated", "Failed to initialize glamor",
        "Could not resolve keysym", "Symbol map for key", "Multiple symbols for",
    ):
        assert message not in journal, journal
    sessions = json.loads(machine.succeed("loginctl list-sessions --json=short"))
    login_sessions = [
        session["session"] for session in sessions
        if session["user"] == "${username}" and session["class"] == "user"
    ]
    assert len(login_sessions) == 1, sessions
    machine.succeed(user(
        "env", "OXBOW_SOCKET=" + environment["OXBOW_SOCKET"],
        "${pkgs.oxbow}/bin/oxctl", "layout", "tiling", "mfact", "0.55",
    ))

    machine.succeed(user(
        "${pkgs.uwsm}/bin/uwsm", "app", "-t", "service", "-u", "desktop-launcher-test.service",
        "--", "${pkgs.fuzzel}/bin/fuzzel",
        "--config=${home.xdg.configFile."fuzzel/fuzzel.ini".source}",
        "--search=Desktop Regression Fixture", "--auto-select",
    ))
    machine.wait_for_file(runtime + "/desktop-test-app.json")
    application_state = json.loads(machine.succeed(
        "cat " + runtime + "/desktop-test-app.json"
    ))
    app_unit = application_state["cgroup"].strip().rsplit("/", 1)[1]
    machine.succeed(user("systemctl", "--user", "is-active", app_unit))
    properties = machine.succeed(user(
        "systemctl", "--user", "show", app_unit,
        "--property=Slice", "--property=ExitType",
    ))
    assert "Slice=app-graphical.slice" in properties, properties
    assert "ExitType=cgroup" in properties, properties
    assert "/app-graphical.slice/" in application_state["cgroup"], application_state
    assert app_unit in application_state["cgroup"], application_state
    for name, value in application_state["environment"].items():
        assert value == environment[name], (name, value, environment[name])

    # Read the real generated Oxbow configuration to invoke its actual logout
    # helper, without maintaining another copy of that command in the test.
    tree = ast.parse(Path("${oxbowInit}").read_text())
    assignment = next(
        node for node in tree.body if isinstance(node, ast.Assign)
        and any(isinstance(target, ast.Name) and target.id == "CONFIG"
                for target in node.targets)
    )
    assert isinstance(assignment.value, ast.Call)
    argument = assignment.value.args[0]
    assert isinstance(argument, ast.Constant)
    configuration = argument.value
    assert isinstance(configuration, str)
    machine.succeed(user(json.loads(configuration)["wayExit"]))
    machine.wait_until_fails(
        user("systemctl", "--user", "is-active", "graphical-session.target")
    )
    machine.wait_until_fails(user("systemctl", "--user", "is-active", app_unit))
    machine.wait_until_fails("kill -0 " + str(application_state["pid"]))
    machine.wait_until_fails(user("pgrep", "--exact", "river"))
    machine.wait_until_fails(user("pgrep", "--exact", "oxbow"))
    for attempt in range(60):
        environment = manager_environment()
        if not {"WAYLAND_DISPLAY", "DISPLAY", "OXBOW_SOCKET", "JD_DESKTOP_READY"} & environment.keys():
            break
        machine.sleep(duration=timedelta(seconds=1))
    else:
        raise AssertionError(environment)
    # A lingering user's manager has a separate class=manager logind session;
    # only the real greetd login must disappear on logout.
    machine.wait_until_fails("loginctl show-session " + login_sessions[0])
  '';
}
