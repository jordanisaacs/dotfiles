{
  pkgs,
  homeConfiguration,
  nixosConfiguration,
}:
let
  home = homeConfiguration.config;
  keyringUnit =
    home.home.file."${home.home.homeDirectory}/.config/systemd/user/gnome-keyring.service".source;
  autostart = home.xdg.configFile.autostart.source;
  bluetoothDirectory =
    nixosConfiguration.config.systemd.services.bluetooth.serviceConfig.ConfigurationDirectory;
in
pkgs.testers.runNixOSTest {
  name = "declarative-boot-services";

  nodes.machine = {
    boot.kernelModules = [ "bluetooth" ];
    hardware.bluetooth.enable = true;
    systemd.services.bluetooth = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ConfigurationDirectory = pkgs.lib.mkForce bluetoothDirectory;
    };
    services.gnome.gnome-keyring.enable = true;
    services.dbus.implementation = "broker";
    users.users.alice = {
      isNormalUser = true;
      uid = 1000;
      linger = true;
    };
    environment.systemPackages = [ pkgs.procps ];
    systemd.tmpfiles.rules = [
      # Reproduce the existing laptop directory, rather than relying on a
      # fresh VM's default 0755 mode that happens to match the old override.
      "d /etc/bluetooth 0555 root root -"
      "d /home/alice/.config 0755 alice users -"
      "d /home/alice/.config/systemd 0755 alice users -"
      "d /home/alice/.config/systemd/user 0755 alice users -"
      "L+ /home/alice/.config/systemd/user/gnome-keyring.service - - - - ${keyringUnit}"
      "L+ /home/alice/.config/autostart - - - - ${autostart}"
    ];
  };

  testScript = ''
    import shlex

    def user(*arguments):
        return shlex.join([
            "runuser", "-u", "alice", "--", "env",
            "XDG_RUNTIME_DIR=/run/user/1000",
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus",
            *arguments,
        ])

    start_all()
    machine.wait_for_unit("user@1000.service")
    machine.wait_for_unit("bluetooth.service")
    machine.succeed("test $(stat -Lc %a /etc/bluetooth) = 555")
    machine.succeed("test -r /etc/bluetooth/main.conf")
    bluetooth_log = machine.succeed("journalctl -b -u bluetooth.service --no-pager")
    assert "mode is different" not in bluetooth_log, bluetooth_log

    # Negative control: the real upstream package has duplicate component
    # launchers when no per-user XDG override is present.
    generator = "${pkgs.systemd}/lib/systemd/user-generators/systemd-xdg-autostart-generator"
    for label, config_home in (("stock", "/tmp/empty-config"), ("fixed", "/home/alice/.config")):
        output = "/tmp/autostart-" + label
        machine.succeed("install -d -o alice -g users " + output + " " + output + "/normal " + output + "/early " + output + "/late")
        machine.succeed(user(
            "env", "XDG_CONFIG_HOME=" + config_home,
            "XDG_CONFIG_DIRS=/run/current-system/sw/etc/xdg",
            generator, output + "/normal", output + "/early", output + "/late",
        ))
        units = machine.succeed("find " + output + " -name '*keyring*' -printf '%f\\n'")
        if label == "stock":
            assert "pkcs11" in units and "secrets" in units, units
        else:
            assert not units, units

    machine.succeed(user("systemctl", "--user", "daemon-reload"))
    machine.succeed(user("systemctl", "--user", "start", "gnome-keyring.service"))
    machine.wait_until_succeeds(user("busctl", "--user", "status", "org.freedesktop.secrets"))
    machine.succeed("test $(pgrep -u alice -fc 'gnome-keyring-daemon --start --foreground') = 1")
    machine.succeed(user(
        "busctl", "--user", "call", "org.freedesktop.secrets",
        "/org/freedesktop/secrets", "org.freedesktop.DBus.Properties", "Get",
        "ss", "org.freedesktop.Secret.Service", "Collections",
    ))
    keyring_log = machine.succeed("journalctl -b _UID=1000 --no-pager")
    assert "already initialized" not in keyring_log, keyring_log
    machine.succeed(user("systemctl", "--user", "stop", "gnome-keyring.service"))
    machine.succeed("test $(pgrep -u alice -fc 'gnome-keyring-daemon --start --foreground') = 0")
  '';
}
