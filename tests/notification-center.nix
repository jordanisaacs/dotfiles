{ pkgs, homeConfiguration }:
let
  home = homeConfiguration.config;
  username = home.home.username;
  directory = home.home.homeDirectory;
  swaync = home.services.swaync.package;
  client = "${swaync}/bin/swaync-client";
  manager =
    pkgs.writers.writePython3Bin "notification-fixture-manager" { flakeIgnore = [ "E501" ]; }
      ''
        import os
        import subprocess

        systemctl = "${pkgs.systemd}/bin/systemctl"
        subprocess.run([systemctl, "--user", "import-environment",
                        "WAYLAND_DISPLAY", "XDG_CURRENT_DESKTOP"], check=True)
        subprocess.run([systemctl, "--user", "start", "notification-fixture-session.target"], check=True)
        executable = "${pkgs.oxbow}/bin/oxbow"
        os.execv(executable, [executable])
      '';
  login = pkgs.writers.writePython3Bin "notification-fixture-login" { flakeIgnore = [ "E501" ]; } ''
    import os

    os.environ.update({
        "WLR_BACKENDS": "headless",
        "WLR_RENDERER": "pixman",
        "WLR_HEADLESS_OUTPUTS": "1",
        "XDG_CURRENT_DESKTOP": "river",
    })
    executable = "${home.jd.graphical.wayland.river.package}/bin/river"
    os.execv(executable, [executable, "-no-xwayland", "-c", "${manager}/bin/notification-fixture-manager"])
  '';
in
pkgs.testers.runNixOSTest {
  name = "native-notification-center";
  nodes.machine = {
    virtualisation = {
      memorySize = 1536;
      cores = 2;
    };
    fonts.packages = [ pkgs.noto-fonts ];
    users.users.${username} = {
      isNormalUser = true;
      uid = 1000;
      home = directory;
      linger = true;
    };
    services.dbus.implementation = "broker";
    programs.dconf.enable = true;
    services.greetd = {
      enable = true;
      settings = {
        initial_session = {
          user = username;
          command = "${login}/bin/notification-fixture-login";
        };
        default_session.command = "${pkgs.coreutils}/bin/sleep infinity";
      };
    };
    systemd = {
      user = {
        targets.notification-fixture-session = {
          requires = [ "graphical-session.target" ];
          bindsTo = [ "graphical-session.target" ];
        };
        services = {
          swaync.environment.GSK_RENDERER = "cairo";
          mako.serviceConfig = {
            Type = "dbus";
            BusName = "org.freedesktop.Notifications";
            ExecStart = "${pkgs.mako}/bin/mako";
          };
        };
      };
      tmpfiles.rules = [
        "d ${directory}/.config 0755 ${username} users -"
        "d ${directory}/.config/swaync 0755 ${username} users -"
        "d ${directory}/.config/systemd 0755 ${username} users -"
        "d ${directory}/.config/systemd/user 0755 ${username} users -"
        "L+ ${directory}/.config/swaync/config.json - - - - ${
          home.xdg.configFile."swaync/config.json".source
        }"
        "L+ ${directory}/.config/swaync/style.css - - - - ${home.xdg.configFile."swaync/style.css".source}"
        "L+ ${directory}/.config/systemd/user/swaync.service - - - - ${
          home.xdg.configFile."systemd/user/swaync.service".source
        }"
      ];
    };
  };
  testScript = ''
    from datetime import timedelta
    import json
    import shlex

    runtime = "/run/user/1000"
    def user(*arguments):
        return shlex.join([
            "runuser", "-u", "${username}", "--", "env",
            "XDG_RUNTIME_DIR=" + runtime,
            "DBUS_SESSION_BUS_ADDRESS=unix:path=" + runtime + "/bus",
            *arguments,
        ])

    def client(*arguments):
        return machine.succeed(user("${client}", *arguments)).strip()

    def events():
        return [json.loads(line) for line in machine.succeed("cat /tmp/notification-stream.jsonl").splitlines()]

    start_all()
    machine.wait_for_unit("greetd.service")
    try:
        machine.wait_until_succeeds(user("systemctl", "--user", "is-active", "graphical-session.target"), timeout=timedelta(seconds=30))
    except Exception:
        print(machine.succeed("journalctl -b --no-pager _UID=1000"))
        print(machine.succeed("journalctl -b --no-pager -u greetd"))
        raise
    river_pid = machine.succeed("pgrep -x river").strip()
    machine.succeed(user("systemctl", "--user", "daemon-reload"))
    machine.succeed(user("systemctl", "--user", "start", "mako.service"))
    machine.succeed(user("systemctl", "--user", "is-active", "mako.service"))
    machine.succeed(user("systemctl", "--user", "stop", "mako.service"))
    machine.succeed(user("ln", "-s", "${
      home.xdg.configFile."systemd/user/mako.service".source
    }", "${directory}/.config/systemd/user/mako.service"))
    machine.succeed(user("systemctl", "--user", "daemon-reload"))
    machine.fail(user("systemctl", "--user", "start", "mako.service"))
    machine.succeed(user("systemctl", "--user", "start", "swaync.service"))
    machine.succeed(user("systemctl", "--user", "is-active", "swaync.service"))
    machine.fail(user("systemctl", "--user", "is-active", "mako.service"))
    machine.succeed(user("systemd-run", "--user", "--unit=notification-stream",
                         "--property=StandardOutput=file:/tmp/notification-stream.jsonl",
                         "${client}", "--subscribe-waybar"))
    machine.wait_until_succeeds("test -s /tmp/notification-stream.jsonl")
    assert client("--count") == "0"
    assert client("--get-dnd") == "false"
    machine.succeed(user("${pkgs.libnotify}/bin/notify-send", "--expire-time=200",
                         "--app-name=Synthetic Fixture", "Saved notification", "Private VM fixture"))
    machine.wait_until_succeeds(user("${client}", "--count") + " | ${pkgs.gnugrep}/bin/grep -qx 1")
    machine.sleep(duration=timedelta(milliseconds=400))
    client("--hide-all")
    assert client("--count") == "1", "Hiding the toast must retain notification history"
    assert client("--toggle-dnd") == "true"
    machine.succeed(user("${pkgs.libnotify}/bin/notify-send", "--app-name=Synthetic Fixture",
                         "Notification while quiet"))
    machine.wait_until_succeeds(user("${client}", "--count") + " | ${pkgs.gnugrep}/bin/grep -qx 2")
    dnd_state = client("--get-dnd")
    assert dnd_state == "true", (dnd_state, machine.succeed("journalctl -b --no-pager _UID=1000"))
    assert any(event["alt"] == "dnd-notification" for event in events()), events()
    client("--toggle-panel")
    state = machine.succeed(user("busctl", "--user", "call", "org.erikreider.swaync.cc",
                                "/org/erikreider/swaync/cc", "org.erikreider.swaync.cc", "GetVisibility"))
    assert "true" in state, state
    client("--close-panel")
    client("--close-all")
    assert client("--count") == "0"
    client("--dnd-off")
    assert client("--get-dnd") == "false"
    machine.succeed(user("systemctl", "--user", "stop", "graphical-session.target"))
    machine.wait_until_fails(user("systemctl", "--user", "is-active", "swaync.service"))
    assert machine.succeed("pgrep -x river").strip() == river_pid
  '';
}
