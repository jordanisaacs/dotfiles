{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [
    ps.dbus-python
    ps.evdev
    ps.pygobject3
  ]);
in
pkgs.testers.runNixOSTest {
  name = "xremap-session-guard";
  nodes.machine = {
    virtualisation.vlans = [ ];
    boot.kernelModules = [ "uinput" ];
    hardware.uinput.enable = true;
    users = {
      groups.xremap = { };
      groups.xremap-jd = { };
      users = {
        jd = {
          isNormalUser = true;
          uid = 1000;
          extraGroups = [ "xremap-jd" ];
        };
        xremap = {
          isSystemUser = true;
          group = "xremap";
          extraGroups = [
            "input"
            "uinput"
            "xremap-jd"
          ];
        };
      };
    };
    systemd.services = pkgs.lib.genAttrs [ "xremap-guard-stock" "xremap-guard-fixed" ] (
      name:
      let
        package = if name == "xremap-guard-stock" then pkgs.xremap.unpatched else pkgs.xremap;
      in
      {
        environment = {
          DBUS_SYSTEM_BUS_ADDRESS = "unix:path=/run/xremap-session-test/bus";
          XREMAP_SOCKET = "/run/xremap-session-test/{uid}/xremap.sock";
        };
        serviceConfig = {
          ExecStart = "${package}/bin/xremap --desktop=socket --device=xremap-session-keyboard --output-device-name=xremap-session-output --no-window-logging --allow-launch=false /run/xremap-session-test/config.json";
          User = "xremap";
          Group = "xremap";
          SupplementaryGroups = [
            "input"
            "uinput"
            "xremap-jd"
          ];
          CapabilityBoundingSet = "";
          DevicePolicy = "closed";
          DeviceAllow = [
            "char-input rw"
            "/dev/uinput rw"
          ];
          NoNewPrivileges = true;
          PrivateNetwork = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          RestrictAddressFamilies = [ "AF_UNIX" ];
          # The stock negative control deliberately blocks in connect().
          TimeoutStopSec = 2;
        };
      }
    );
    environment.systemPackages = [
      python
      pkgs.dbus
    ];
    environment.etc."xremap-session-fixture.py".source = ./xremap_session_fixture.py;
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    # Only a VM-created keyboard is opened; the host has no input involvement.
    output = machine.succeed("${python}/bin/python /etc/xremap-session-fixture.py test", timeout=120)
    print(output)
  '';
}
