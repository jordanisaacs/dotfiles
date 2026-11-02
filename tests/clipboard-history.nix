{ pkgs, homeConfiguration }:
let
  home = homeConfiguration.config;
  username = home.home.username;
  directory = home.home.homeDirectory;
  python = pkgs.python3.withPackages (packages: [ packages.pygobject3 ]);
  fixture = pkgs.stdenvNoCC.mkDerivation {
    pname = "clipboard-keyring-fixture";
    version = "1";
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.wrapGAppsNoGuiHook
      pkgs.gobject-introspection
    ];
    buildInputs = [ pkgs.libsecret ];
    installPhase = ''
      install -Dm755 ${./clipboard_keyring_fixture.py} "$out/bin/clipboard-keyring-fixture"
      substituteInPlace "$out/bin/clipboard-keyring-fixture" \
        --replace-fail '#!/usr/bin/env python3' '#!${python}/bin/python3'
    '';
    postFixup = ''
      wrapProgram "$out/bin/clipboard-keyring-fixture" \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.systemd ]} \
        --set GNOME_KEYRING_DAEMON ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon
    '';
  };
  unitNames = [
    "gnome-keyring"
    "clipboard-vault"
    "cliphist"
    "cliphist-images"
  ];
  manager = pkgs.writers.writePython3Bin "clipboard-fixture-manager" { flakeIgnore = [ "E501" ]; } ''
    import os
    import subprocess

    systemctl = "${pkgs.systemd}/bin/systemctl"
    subprocess.run([systemctl, "--user", "import-environment", "WAYLAND_DISPLAY"], check=True)
    subprocess.run([systemctl, "--user", "start", "clipboard-fixture-session.target"], check=True)
    executable = "${pkgs.oxbow}/bin/oxbow"
    os.execv(executable, [executable])
  '';
  login = pkgs.writers.writePython3Bin "clipboard-fixture-login" { flakeIgnore = [ "E501" ]; } ''
    import os

    os.environ.update({"WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman", "WLR_HEADLESS_OUTPUTS": "1"})
    executable = "${home.jd.graphical.wayland.river.package}/bin/river"
    os.execv(executable, [executable, "-no-xwayland", "-c", "${manager}/bin/clipboard-fixture-manager"])
  '';
in
pkgs.testers.runNixOSTest {
  name = "keyring-encrypted-clipboard-history";
  nodes.machine = {
    virtualisation = {
      memorySize = 2048;
      cores = 2;
    };
    programs.fuse.enable = true;
    boot.kernelModules = [ "fuse" ];
    fonts.packages = [ pkgs.noto-fonts ];
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
          command = "${login}/bin/clipboard-fixture-login";
        };
        default_session.command = "${pkgs.coreutils}/bin/sleep infinity";
      };
    };
    systemd.user.targets.clipboard-fixture-session = {
      requires = [
        "graphical-session-pre.target"
        "graphical-session.target"
      ];
      bindsTo = [ "graphical-session.target" ];
    };
    environment.systemPackages = [
      pkgs.wl-clipboard
      pkgs.wtype
      pkgs.xdg-utils
      pkgs.gnome-keyring
      pkgs.libsecret
      fixture
    ];
    systemd.tmpfiles.rules = [
      "d ${directory}/.config 0755 ${username} users -"
      "d ${directory}/.config/systemd 0755 ${username} users -"
      "d ${directory}/.config/systemd/user 0755 ${username} users -"
    ]
    ++ map (
      name:
      "L+ ${directory}/.config/systemd/user/${name}.service - - - - ${
        home.xdg.configFile."systemd/user/${name}.service".source
      }"
    ) unitNames;
  };
  testScript = ''
    from datetime import timedelta
    import shlex

    runtime = "/run/user/1000"
    mount = runtime + "/clipboard-history/plain"
    database = mount + "/db"
    cipher = "${directory}/.local/state/clipboard-history/vault"
    cliphist = "${home.services.cliphist.package}/bin/cliphist"
    picker = "${home.jd.graphical.wayland.clipboard.package}/bin/clipboard-history"
    probe = "${fixture}/bin/clipboard-keyring-fixture"
    vault = "${home.jd.graphical.wayland.clipboard.vaultPackage}/bin/clipboard-vault"
    def user(*arguments):
        return shlex.join([
            "runuser", "-u", "${username}", "--", "env",
            "XDG_RUNTIME_DIR=" + runtime,
            "DBUS_SESSION_BUS_ADDRESS=unix:path=" + runtime + "/bus",
            *arguments,
        ])

    start_all()
    machine.wait_for_unit("greetd.service")
    machine.wait_until_succeeds(user("systemctl", "--user", "is-active", "graphical-session.target"), timeout=timedelta(seconds=30))
    machine.succeed(user("systemctl", "--user", "daemon-reload"))
    machine.succeed(user("systemctl", "--user", "start", "gnome-keyring.service"))
    machine.wait_until_succeeds("test -S " + runtime + "/keyring/control")
    try:
        machine.succeed(user(probe, "prepare"))
    except Exception:
        print(machine.succeed("journalctl -b --no-pager _UID=1000"))
        print(machine.succeed(user("busctl", "--user", "tree", "org.freedesktop.secrets")))
        print(machine.succeed("find ${directory}/.local/share/keyrings -type f"))
        raise
    machine.succeed(user(vault, "check"))
    try:
        machine.succeed(user("systemctl", "--user", "start", "cliphist.service", "cliphist-images.service"))
    except Exception:
        print(machine.succeed("journalctl -b --no-pager _UID=1000"))
        raise
    machine.succeed(user("mountpoint", "-q", mount))
    machine.succeed(user("test", "-w", mount))
    environment = dict(line.split("=", 1) for line in machine.succeed(user("systemctl", "--user", "show-environment")).splitlines() if "=" in line)
    wayland = "WAYLAND_DISPLAY=" + environment["WAYLAND_DISPLAY"]
    marker = "encrypted-clipboard-private-native-fixture-marker"
    machine.succeed(user("env", wayland, "wl-copy", marker))
    machine.wait_until_succeeds(user("test", "-s", database))
    assert machine.succeed(user("stat", "-c", "%a", database)).strip() == "600"
    assert machine.succeed(user("stat", "-c", "%a", cipher)).strip() == "700"
    machine.succeed(user(probe, "inspect"))
    machine.succeed(user(probe, "wrong-key"))
    assert marker in machine.succeed(user(cliphist, "-db-path", database, "list"))
    machine.succeed(user(probe, "lock"))
    machine.wait_until_fails(user("mountpoint", "-q", mount))
    machine.wait_until_fails(user("systemctl", "--user", "is-active", "cliphist.service"))
    machine.fail(user(vault, "check"))
    machine.succeed(user("systemctl", "--user", "start", "cliphist.service", "cliphist-images.service"))
    machine.fail(user("mountpoint", "-q", mount))
    machine.fail(user("test", "-f", database))
    machine.succeed(user(probe, "unlock"))
    machine.succeed(user("systemctl", "--user", "start", "cliphist.service", "cliphist-images.service"))
    machine.succeed(user("mountpoint", "-q", mount))
    assert marker in machine.succeed(user(cliphist, "-db-path", database, "list"))
    # Keep the private headless seat keyboard-capable between input clients.
    machine.succeed(user("systemd-run", "--user", "--unit=clipboard-fixture-keyboard", "--collect", "--setenv=" + wayland, "wtype", "-k", "F35", "-s", "300000"))
    machine.succeed(user("env", wayland, "CLIPHIST=" + cliphist, "PICKER=" + picker, probe, "interactions"))
    machine.fail(user("test", "-e", "${directory}/.cache/cliphist/db"))
    machine.succeed(user("systemctl", "--user", "stop", "gnome-keyring.service"))
    machine.wait_until_fails(user("mountpoint", "-q", mount))
    machine.wait_until_fails(user("systemctl", "--user", "is-active", "cliphist.service"))
    machine.succeed(user("systemctl", "--user", "start", "gnome-keyring.service"))
    machine.succeed(user(probe, "unlock"))
    machine.succeed(user(vault, "unlock"))
    machine.succeed(user("mountpoint", "-q", mount))
    machine.succeed(user("systemctl", "--user", "stop", "graphical-session.target"))
    machine.wait_until_fails(user("mountpoint", "-q", mount))
    machine.fail(user("test", "-f", database))
    assert machine.succeed("pgrep -x river").strip()
  '';
}
