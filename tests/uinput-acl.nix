{
  pkgs,
  repair ? true,
}:
pkgs.testers.runNixOSTest {
  name = "uinput-owning-group-acl";
  nodes.machine =
    { config, lib, ... }:
    {
      imports = [ ../modules/system/graphical/input-style.nix ];
      virtualisation.vlans = [ ];
      networking.dhcpcd.enable = false;
      users.users.jd = {
        isNormalUser = true;
        uid = 1000;
      };
      jd.graphical.inputRemapping = {
        enable = true;
        users = [ "jd" ];
      };
      # This test opens and closes the VM's uinput node without creating a
      # virtual device or injecting events. The full remapper need not run.
      systemd.services.desktop-input.wantedBy = lib.mkForce [ ];
      environment.systemPackages = [
        pkgs.python3
        pkgs.acl
        pkgs.util-linux
      ];
      environment.etc = {
        "uinput-acl-probe.py".source = ./uinput_acl_probe.py;
        "uinput-acl-repair.conf".text = lib.concatStringsSep "\n" (
          lib.optionals repair (lib.filter (lib.hasPrefix "a+ /dev/uinput ") config.systemd.tmpfiles.rules)
        );
      };
    };
  testScript = ''
    from datetime import timedelta

    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_until_succeeds("test -c /dev/uinput")
    print(machine.succeed("python /etc/uinput-acl-probe.py", timeout=timedelta(seconds=30)))
  '';
}
