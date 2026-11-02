{ pkgs, homeConfiguration }:
let
  home = homeConfiguration.config;
  username = home.home.username;
  directory = home.home.homeDirectory;
  unitNames = [
    "river-wm-oxbow"
    "river-wm-reka"
    "river-input"
    "waybar"
  ];
  unit = name: home.xdg.configFile."systemd/user/${name}.service".source;
  clickCommands = pkgs.writeText "waybar-settings-actions.json" (
    builtins.toJSON (
      pkgs.lib.genAttrs [ "network" "pulseaudio" ] (
        name: (builtins.head home.programs.waybar.settings).${name}.on-click
      )
    )
  );
  trayPython = pkgs.python3.withPackages (python: [ python.pygobject3 ]);
  trayFixture = pkgs.stdenvNoCC.mkDerivation {
    name = "status-tray-fixture";
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.wrapGAppsHook3
      pkgs.gobject-introspection
      trayPython
    ];
    buildInputs = [
      pkgs.gtk3
      pkgs.libappindicator-gtk3
    ];
    installPhase = ''
      install -Dm755 ${./waybar_tray_fixture.py} "$out/bin/status-tray-fixture"
      substituteInPlace "$out/bin/status-tray-fixture" \
        --replace-fail '#!/usr/bin/env python3' '#!${trayPython}/bin/python3'
    '';
  };
  login = pkgs.writers.writePython3Bin "status-bar-test-login" { } ''
    import os

    xwayland = (
        "${pkgs.coreutils}"
        "/bin/false"
    )
    os.environ.update({
        "WLR_BACKENDS": "headless",
        "WLR_RENDERER": "pixman",
        "WLR_HEADLESS_OUTPUTS": "2",
        "WLR_XWAYLAND": xwayland,
    })
    executable = (
        "${builtins.dirOf (toString home.home.file.".winitrc".source)}"
        "/${builtins.baseNameOf (toString home.home.file.".winitrc".source)}"
    )
    os.execv(executable, [executable, "--window-manager", "oxbow"])
  '';
  compositorStop =
    home.xdg.configFile."systemd/user/wayland-wm@river.service.d/50-window-managers.conf".source;
  profile = pkgs.buildEnv {
    name = "status-bar-fixture-profile";
    paths = [
      home.home.pointerCursor.package
      home.jd.graphical.wayland.river.switchPackage
    ];
  };
in
pkgs.testers.runNixOSTest {
  name = "river-waybar-tray-session";
  nodes.machine = {
    virtualisation = {
      memorySize = 2048;
      cores = 2;
    };
    programs.uwsm.enable = true;
    fonts.packages = [
      pkgs.noto-fonts
      pkgs.symbols-nerd-font
    ];
    users.users.${username} = {
      isNormalUser = true;
      uid = 1000;
      home = directory;
      linger = true;
    };
    services.dbus.implementation = "broker";
    services.greetd = {
      enable = true;
      settings = {
        initial_session = {
          user = username;
          command = "${login}/bin/status-bar-test-login";
        };
        default_session.command = "${pkgs.coreutils}/bin/sleep infinity";
      };
    };
    systemd.tmpfiles.rules = [
      "d ${directory}/.config 0755 ${username} users -"
      "d ${directory}/.config/river 0755 ${username} users -"
      "d ${directory}/.config/oxbow 0755 ${username} users -"
      "d ${directory}/.config/reka 0755 ${username} users -"
      "d ${directory}/.config/waybar 0755 ${username} users -"
      "d ${directory}/.config/systemd 0755 ${username} users -"
      "d ${directory}/.config/systemd/user 0755 ${username} users -"
      "d ${directory}/.config/systemd/user/graphical-session.target.wants 0755 ${username} users -"
      "d ${directory}/.config/systemd/user/wayland-wm@river.service.d 0755 ${username} users -"
      "L+ ${directory}/.config/systemd/user/wayland-wm@river.service.d/50-window-managers.conf - - - - ${compositorStop}"
      "L+ ${directory}/.winitrc - - - - ${home.home.file.".winitrc".source}"
      "L+ ${directory}/.config/river/init - - - - ${home.xdg.configFile."river/init".source}"
      "L+ ${directory}/.config/river/config.rh - - - - ${home.xdg.configFile."river/config.rh".source}"
      "L+ ${directory}/.config/oxbow/init - - - - ${home.xdg.configFile."oxbow/init".source}"
      "L+ ${directory}/.config/reka/init.el - - - - ${home.xdg.configFile."reka/init.el".source}"
      "L+ ${directory}/.config/waybar/config - - - - ${home.xdg.configFile."waybar/config".source}"
      "L+ ${directory}/.config/waybar/style.css - - - - ${home.xdg.configFile."waybar/style.css".source}"
      "L+ ${directory}/.config/systemd/user/graphical-session.target.wants/waybar.service - - - - ${unit "waybar"}"
      "L+ ${home.home.profileDirectory} - - - - ${profile}"
    ]
    ++ map (
      name: "L+ ${directory}/.config/systemd/user/${name}.service - - - - ${unit name}"
    ) unitNames;
  };
  testScript = ''
    from datetime import timedelta
    import json
    import re
    import shlex

    runtime = "/run/user/1000"

    def user(*arguments):
        return shlex.join([
            "runuser", "-u", "${username}", "--", "env",
            "XDG_RUNTIME_DIR=" + runtime,
            "DBUS_SESSION_BUS_ADDRESS=unix:path=" + runtime + "/bus",
            *arguments,
        ])

    def environment():
        return dict(line.split("=", 1) for line in machine.succeed(user(
            "systemctl", "--user", "show-environment",
        )).splitlines() if "=" in line)

    def bar_log():
        return machine.succeed("journalctl -b --no-pager _SYSTEMD_USER_UNIT=waybar.service _UID=1000")

    def tray_items():
        return machine.succeed(user(
            "busctl", "--user", "get-property", "org.kde.StatusNotifierWatcher",
            "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher",
            "RegisteredStatusNotifierItems",
        ))

    def wait_for_tray():
        for attempt in range(50):
            status, items = machine.execute(user(
                "busctl", "--user", "get-property", "org.kde.StatusNotifierWatcher",
                "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher",
                "RegisteredStatusNotifierItems",
            ))
            if status == 0 and "status_bar_regression" in items:
                return
            machine.sleep(duration=timedelta(milliseconds=200))
        raise AssertionError(items)

    start_all()
    machine.wait_for_unit("greetd.service")
    machine.wait_until_succeeds(user("systemctl", "--user", "is-active", "waybar.service"))
    display = "WAYLAND_DISPLAY=" + environment()["WAYLAND_DISPLAY"]
    # Exercise two actual outputs with different native scale factors.
    machine.succeed(user("env", display, "${pkgs.wlr-randr}/bin/wlr-randr",
        "--output", "HEADLESS-1", "--scale", "1.25"))
    machine.wait_until_succeeds(user("busctl", "--user", "status", "org.kde.StatusNotifierWatcher"))
    # A settings action must run in Waybar's real process environment, rather
    # than a clean login shell that can hide its service's PATH regression.
    bar_pid = machine.succeed(user("systemctl", "--user", "show", "waybar.service", "-p", "MainPID", "--value")).strip()
    bar_environment = dict(field.split("=", 1) for field in machine.succeed(
        "cat /proc/" + bar_pid + "/environ",
    ).split(chr(0)) if "=" in field)
    actions = json.loads(machine.succeed("cat ${clickCommands}"))
    for name in ("network", "pulseaudio"):
        machine.succeed(user("env", "-i",
            *[key + "=" + value for key, value in bar_environment.items()],
            *shlex.split(actions[name]),
        ))
    for executable in ("wpa_gui", "pavucontrol"):
        machine.wait_until_succeeds(user("systemctl", "--user", "is-active", "app-river-" + executable + "@*.service"))
    application_units = json.loads(machine.succeed(user(
        "systemctl", "--user", "list-units", "--output=json", "--type=service", "app-*",
    )))
    for executable in ("wpa_gui", "pavucontrol"):
        matching = [unit for unit in application_units if executable in unit["unit"]]
        assert len(matching) == 1 and matching[0]["active"] == "active", matching
        group = machine.succeed(user("systemctl", "--user", "show", matching[0]["unit"], "-p", "ControlGroup", "--value"))
        assert "/app-graphical.slice/" in group, group
    machine.succeed(user(
        "systemd-run", "--user", "--unit=status-tray-fixture", "--collect",
        "--setenv=" + display,
        "${trayFixture}/bin/status-tray-fixture",
    ))
    wait_for_tray()
    registered = machine.succeed(user("busctl", "--user", "get-property", "org.kde.StatusNotifierWatcher",
        "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher", "IsStatusNotifierHostRegistered"))
    assert registered.strip() == "b true", registered
    item = next(value for value in shlex.split(tray_items()) if "status_bar_regression" in value)
    service, _, path = item.partition("/")
    path = "/" + path
    menu = shlex.split(machine.succeed(user("busctl", "--user", "get-property",
        service, path, "org.kde.StatusNotifierItem", "Menu")))[1]
    layout = machine.succeed(user("busctl", "--user", "call", service, menu,
        "com.canonical.dbusmenu", "GetLayout", "iias", "0", "1", "0"))
    assert "Regression action" in layout, layout
    log = bar_log()
    assert "for output: HEADLESS-1" in log and "for output: HEADLESS-2" in log, log
    heights = [int(value) for value in re.findall(r"height: (\d+)\)", log)]
    assert heights and all(30 <= height <= 36 for height in heights), heights
    for bad in ("Error parsing", "not a valid property", "Unknown module", "Unknown CSS"):
        assert bad not in log, log
    machine.succeed(user("env", display, "${pkgs.grim}/bin/grim", "-o", "HEADLESS-1", runtime + "/waybar-first.png"))
    machine.copy_from_machine(runtime + "/waybar-first.png", "waybar-first.png")

    original_bar = machine.succeed(user("systemctl", "--user", "show", "waybar.service", "-p", "MainPID", "--value")).strip()
    machine.succeed(user("env", display, "${pkgs.wlr-randr}/bin/wlr-randr", "--output", "HEADLESS-1", "--off"))
    assert machine.succeed(user("systemctl", "--user", "show", "waybar.service", "-p", "MainPID", "--value")).strip() == original_bar
    assert "status_bar_regression" in tray_items()
    machine.succeed(user("env", display, "${pkgs.grim}/bin/grim", "-o", "HEADLESS-2", runtime + "/waybar-external.png"))
    machine.copy_from_machine(runtime + "/waybar-external.png", "waybar-external.png")
    machine.succeed(user("env", display, "${pkgs.wlr-randr}/bin/wlr-randr", "--output", "HEADLESS-1", "--on", "--scale", "1.25"))

    switch = "${home.jd.graphical.wayland.river.switchPackage}/bin/river-wm"
    machine.succeed(user(switch, "reka"))
    machine.wait_until_succeeds(user("systemctl", "--user", "is-active", "waybar.service"))
    wait_for_tray()
    machine.wait_until_succeeds(user(
        "${pkgs.reka-emacs}/bin/emacsclient", "--socket-name", "reka", "--eval",
        '(let ((apps (prin1-to-string (mapcar (lambda (buffer) (with-current-buffer buffer (list (buffer-name) reka-app-id))) (append (reka--list-buffers) nil))))) (unless (and (string-match-p "wpa_gui" apps) (string-match-p "pavucontrol" apps)) (error "Waiting for settings windows: %s" apps)) apps)',
    ), timeout=timedelta(seconds=20))
    machine.fail("pgrep -u ${username} -x oxctl")
    machine.succeed(user(switch, "oxbow"))
    wait_for_tray()
    machine.succeed(user("${pkgs.uwsm}/bin/uwsm", "stop"))
    machine.wait_until_fails(user("systemctl", "--user", "is-active", "waybar.service"))
    result = machine.succeed(user("systemctl", "--user", "show", "waybar.service", "-p", "Result"))
    assert "Result=success" in result, result
  '';
}
