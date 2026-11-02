{
  pkgs,
  homeConfiguration,
  nativeHealth ? false,
}:
let
  home =
    (homeConfiguration.extendModules {
      modules = [
        ({ lib, ... }: {
          jd.graphical.wayland = {
            river.package = lib.mkForce (if nativeHealth then pkgs.river-reka-with-health else pkgs.river-reka);
            logout.healthPackage = lib.mkForce (if nativeHealth then pkgs.river-health else null);
          };
        })
      ];
    }).config;
  username = home.home.username;
  directory = home.home.homeDirectory;
  python = pkgs.python3.withPackages (packages: [ packages.pygobject3 ]);
  fixture = pkgs.stdenvNoCC.mkDerivation {
    name = "logout-consent-fixture";
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.wrapGAppsHook3
      pkgs.gobject-introspection
    ];
    buildInputs = [
      pkgs.gtk3
      pkgs.at-spi2-core
    ];
    installPhase = ''
      install -Dm755 ${./logout_fixture.py} "$out/bin/logout-consent-fixture"
      install -Dm755 ${./logout_accessibility.py} "$out/bin/logout-accessibility"
      substituteInPlace "$out/bin/logout-accessibility" \
        --replace-fail '#!/usr/bin/env python3' '#!${python}/bin/python3'
      substituteInPlace "$out/bin/logout-consent-fixture" \
        --replace-fail '#!/usr/bin/env python3' '#!${python}/bin/python3'
    '';
  };
  login = pkgs.writers.writePython3Bin "logout-test-login" { } ''
    import os

    xwayland = (
        "${pkgs.coreutils}"
        "/bin/false"
    )
    os.environ.update({
        "WLR_BACKENDS": "headless",
        "WLR_RENDERER": "pixman",
        "WLR_HEADLESS_OUTPUTS": "1",
        "WLR_XWAYLAND": xwayland,
    })
    executable = (
        "${builtins.dirOf (toString home.home.file.".winitrc".source)}"
        "/${builtins.baseNameOf (toString home.home.file.".winitrc".source)}"
    )
    os.execv(executable, [executable, "--window-manager", "oxbow"])
  '';
  units = [
    "river-wm-oxbow"
    "river-wm-reka"
    "river-input"
  ];
  profile = pkgs.buildEnv {
    name = "logout-fixture-profile";
    paths = [
      home.home.pointerCursor.package
      home.jd.graphical.wayland.river.switchPackage
    ];
  };
in
pkgs.testers.runNixOSTest {
  name = "river-graceful-logout${pkgs.lib.optionalString nativeHealth "-health"}";
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
      home = directory;
      linger = true;
    };
    services = {
      dbus.implementation = "broker";
      gnome.at-spi2-core.enable = true;
      greetd = {
        enable = true;
        settings = {
          initial_session = {
            user = username;
            command = "${login}/bin/logout-test-login";
          };
          default_session.command = "${pkgs.coreutils}/bin/sleep infinity";
        };
      };
    };
    systemd.user.services.app-logout-fixture = {
      unitConfig.PartOf = "graphical-session.target";
      serviceConfig = {
        ExecStart = "${fixture}/bin/logout-consent-fixture";
        Slice = "app-graphical.slice";
        # The force-path test deliberately stops only its own private client.
        TimeoutStopSec = 2;
      };
    };
    systemd.tmpfiles.rules = [
      "d ${directory}/.config 0755 ${username} users -"
      "d ${directory}/.config/river 0755 ${username} users -"
      "d ${directory}/.config/oxbow 0755 ${username} users -"
      "d ${directory}/.config/reka 0755 ${username} users -"
      "d ${directory}/.config/systemd 0755 ${username} users -"
      "d ${directory}/.config/systemd/user 0755 ${username} users -"
      "d ${directory}/.config/systemd/user/wayland-wm@river.service.d 0755 ${username} users -"
      "L+ ${directory}/.config/systemd/user/wayland-wm@river.service.d/50-window-managers.conf - - - - ${
        home.xdg.configFile."systemd/user/wayland-wm@river.service.d/50-window-managers.conf".source
      }"
      "L+ ${directory}/.winitrc - - - - ${home.home.file.".winitrc".source}"
      "L+ ${directory}/.config/river/init - - - - ${home.xdg.configFile."river/init".source}"
      "L+ ${directory}/.config/river/config.rh - - - - ${home.xdg.configFile."river/config.rh".source}"
      "L+ ${directory}/.config/oxbow/init - - - - ${home.xdg.configFile."oxbow/init".source}"
      "L+ ${directory}/.config/reka/init.el - - - - ${home.xdg.configFile."reka/init.el".source}"
      "L+ ${home.home.profileDirectory} - - - - ${profile}"
    ]
    ++ map (
      name:
      "L+ ${directory}/.config/systemd/user/${name}.service - - - - ${
        home.xdg.configFile."systemd/user/${name}.service".source
      }"
    ) units;
  };
  testScript = ''
    from datetime import timedelta
    import json
    import shlex

    runtime = "/run/user/1000"
    application = "dev.snowytrees.DesktopLogout"
    client = "dev.snowytrees.LogoutFixture"
    helper = "${home.jd.graphical.wayland.logout.package}/bin/desktop-logout"
    native_health = ${if nativeHealth then "True" else "False"}

    def ui():
        return json.loads(machine.succeed(user("${fixture}/bin/logout-accessibility")))

    def wait_ui(text):
        for attempt in range(150):
            tree = ui()
            if any(text in node["name"] for node in tree):
                return tree
            machine.sleep(duration=timedelta(milliseconds=100))
        raise AssertionError(tree)

    def user(*arguments):
        return shlex.join(["runuser", "-u", "${username}", "--", "env",
            "XDG_RUNTIME_DIR=" + runtime, "DBUS_SESSION_BUS_ADDRESS=unix:path=" + runtime + "/bus", *arguments])

    def state():
        return json.loads(machine.succeed("cat " + runtime + "/logout-fixture.json"))

    def action(app, name):
        machine.succeed(user("${pkgs.glib.bin}/bin/gapplication", "action", app, name))

    def wait_action(name):
        for attempt in range(60):
            status, value = machine.execute(user("busctl", "--user", "call", application,
                "/dev/snowytrees/DesktopLogout", "org.gtk.Actions", "Describe", "s", name))
            if status == 0 and "true" in value:
                return
            machine.sleep(duration=timedelta(milliseconds=100))
        raise AssertionError(value)

    def show_logout():
        machine.succeed(user("${pkgs.uwsm}/bin/uwsm", "app", "-t", "service", "--", helper))
        wait_action("confirm")

    def keyboard_logout():
        # Real modifier/key events exercise River's translated/untranslated
        # bindings; direct helper invocation cannot catch a stock exit bypass.
        machine.succeed(user("env", wayland, "${pkgs.wtype}/bin/wtype",
            "-M", "logo", "-M", "shift", "-k", "q", "-m", "shift", "-m", "logo"))
        wait_action("confirm")

    def cancel_logout():
        action(application, "cancel")
        machine.wait_until_fails(user("busctl", "--user", "status", application))
        machine.succeed(user("systemctl", "--user", "is-active", "graphical-session.target", "app-logout-fixture.service"))

    def wait_requests(number):
        for attempt in range(60):
            value = state()
            if value["close_requests"] >= number:
                assert value["close_requests"] == number, value
                return
            machine.sleep(duration=timedelta(milliseconds=100))
        raise AssertionError(value)

    start_all()
    machine.wait_until_succeeds(user("systemctl", "--user", "is-active", "graphical-session.target"))
    environment = dict(line.split("=", 1) for line in machine.succeed(user("systemctl", "--user", "show-environment")).splitlines() if "=" in line)
    wayland = "WAYLAND_DISPLAY=" + environment["WAYLAND_DISPLAY"]
    # Give the private headless seat the keyboard capability of the laptop,
    # before any app or save dialog is mapped.
    machine.succeed(user("systemd-run", "--user", "--unit=logout-keyboard", "--collect",
        "--setenv=" + wayland, "${pkgs.wtype}/bin/wtype", "-k", "F35", "-s", "300000"))
    machine.succeed(user("systemctl", "--user", "start", "app-logout-fixture.service"))
    machine.wait_for_file(runtime + "/logout-fixture.json")
    river_pid = machine.succeed(user("systemctl", "--user", "show", "wayland-wm@river.service", "-p", "MainPID", "--value")).strip()
    client_pid = state()["pid"]

    # The real logout chord must reach confirmation, not Oxbow's inherited
    # immediate session-exit binding. Cancel does not send any close request.
    keyboard_logout()
    assert state()["close_requests"] == 0, state()
    wait_ui("Close applications and log out?")
    wait_ui("Responding" if native_health else "Waiting for app")
    cancel_logout()
    assert state()["pid"] == client_pid

    # Inspect Oxbow's real parsed bindings: textual Q is folded to q, while
    # its built-in uppercase-Q binding uses a distinct XKB keysym. It must use
    # the same tested confirmation command, with no immediate session-exit path.
    keymap = json.loads(machine.succeed(user("env", "OXBOW_SOCKET=" + environment["OXBOW_SOCKET"],
        "${pkgs.oxbow}/bin/oxctl", "keymap", "list", "--json")))
    bindings = keymap["bindings"]
    uppercase = next(binding for binding in bindings if binding["keybind"] == "Super+Q")
    shifted = next(binding for binding in bindings if binding["keybind"] == "Super+Shift+q")
    immediate_exits = [binding for binding in bindings
        if binding["command"][0].lower() == "session"
        and binding["command"][1][0].lower() == "exit"]
    assert not immediate_exits, immediate_exits
    assert uppercase["command"] == shifted["command"], (uppercase, shifted)

    # Native Oxbow closes by stable window identifier, allowing a save dialog.
    show_logout()
    manager_environment = dict(line.split("=", 1) for line in machine.succeed(user("systemctl", "--user", "show-environment")).splitlines() if "=" in line)
    oxbow_inventory = json.loads(machine.succeed(user("env", "OXBOW_SOCKET=" + manager_environment["OXBOW_SOCKET"], "${pkgs.oxbow}/bin/oxctl", "window", "list", "--json")))
    fixture_identifier = next(window["identifier"] for window in oxbow_inventory if window["app_id"] == client)
    action(application, "confirm")
    wait_requests(1)
    assert state()["dialog"], state()
    action(client, "cancel-close")
    wait_action("force")
    wait_ui("Responding" if native_health else "Waiting for app")
    cancel_logout()
    machine.sleep(duration=timedelta(milliseconds=500))
    assert state()["close_requests"] == 1, state()

    switch = "${home.jd.graphical.wayland.river.switchPackage}/bin/river-wm"
    machine.succeed(user(switch, "reka"))
    emacs = "${pkgs.reka-emacs}/bin/emacsclient"

    def evaluate(expression):
        return machine.succeed(user(emacs, "--socket-name", "reka", "--eval", expression))

    target = '(seq-find (lambda (buffer) (equal (buffer-local-value (quote reka-app-id) buffer) "dev.snowytrees.LogoutFixture")) (append (reka--list-buffers) nil))'
    machine.wait_until_succeeds(user(emacs, "--socket-name", "reka", "--eval",
        '(unless ' + target + ' (error "Waiting for fixture buffer"))'))
    reka_inventory = json.loads(json.loads(evaluate('(jd-reka-logout-inventory)')))
    assert len(reka_inventory) == 1, reka_inventory
    assert reka_inventory[0]["identifier"] == fixture_identifier, reka_inventory
    identifier = evaluate('(buffer-local-value (quote reka-identifier) ' + target + ')')
    machine.wait_until_succeeds(user(emacs, "--socket-name", "reka", "--eval",
        '(unless (buffer-local-value (quote reka-floating-geometry) ' + target + ') (error "Waiting for native displayed geometry"))'))
    # Exercise the same native function on the old/fixed fork. A refusal must
    # keep the live application buffer, geometry, identifier and input usable.
    evaluate('(with-current-buffer ' + target + ' (reka-close-window reka-handle reka-window))')
    wait_requests(2)
    action(client, "cancel-close")
    machine.sleep(duration=timedelta(milliseconds=500))
    assert state()["close_requests"] == 2, state()
    assert evaluate('(buffer-local-value (quote reka-identifier) ' + target + ')') == identifier
    assert evaluate('(and (get-buffer-window ' + target + ' t) t)').strip() == "t"
    previous_text = state()["text"]
    machine.succeed(user("env", wayland, "${pkgs.wtype}/bin/wtype", "x"))
    for attempt in range(30):
        if state()["text"] != previous_text:
            break
        machine.sleep(duration=timedelta(milliseconds=100))
    else:
        raise AssertionError(state())

    # The same physical chord must use the guard after a ReKa handoff too.
    keyboard_logout()
    action(application, "confirm")
    wait_requests(3)
    wait_action("force")
    action(client, "cancel-close")
    cancel_logout()
    assert state()["pid"] == client_pid
    assert machine.succeed(user("systemctl", "--user", "show", "wayland-wm@river.service", "-p", "MainPID", "--value")).strip() == river_pid

    # Only accepting the application's own save/close ends the normal session.
    show_logout()
    action(application, "confirm")
    wait_requests(4)
    action(client, "save-and-close")
    machine.wait_until_fails(user("systemctl", "--user", "is-active", "graphical-session.target"))
    machine.wait_until_fails(user("systemctl", "--user", "is-active", "wayland-wm@river.service"))

    # A second private login proves force is explicit even for a genuinely
    # stopped client. No host application or user data is involved.
    machine.shutdown()
    machine.start()
    machine.wait_until_succeeds(user("systemctl", "--user", "is-active", "graphical-session.target"))
    machine.succeed(user("systemctl", "--user", "start", "app-logout-fixture.service"))
    machine.wait_until_succeeds(user("busctl", "--user", "status", client))
    forced_pid = machine.succeed(user("systemctl", "--user", "show", "app-logout-fixture.service", "-p", "MainPID", "--value")).strip()
    show_logout()
    action(application, "confirm")
    wait_requests(1)
    machine.succeed(user("systemctl", "--user", "kill", "--kill-whom=main", "--signal=STOP", "app-logout-fixture.service"))
    wait_action("force")
    machine.sleep(duration=timedelta(milliseconds=500))
    machine.succeed(user("systemctl", "--user", "is-active", "graphical-session.target"))
    if native_health:
        wait_ui("Not responding")
        machine.succeed(user("systemctl", "--user", "is-active", "graphical-session.target"))
        machine.succeed(user("systemctl", "--user", "kill", "--kill-whom=main", "--signal=CONT", "app-logout-fixture.service"))
        wait_ui("Responding")
        machine.succeed(user("systemctl", "--user", "kill", "--kill-whom=main", "--signal=STOP", "app-logout-fixture.service"))
    action(application, "force")
    wait_action("force-confirm")
    machine.succeed(user("systemctl", "--user", "is-active", "graphical-session.target"))
    action(application, "force-confirm")
    machine.wait_until_fails(user("systemctl", "--user", "is-active", "graphical-session.target"))
    machine.wait_until_fails(user("systemctl", "--user", "is-active", "app-logout-fixture.service"))
    machine.wait_until_fails("test -e /proc/" + forced_pid)
  '';
}
