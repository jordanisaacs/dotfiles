{ pkgs, disko }:
pkgs.testers.runNixOSTest {
  name = "disko-disposable-encrypted-installation";
  nodes.machine = { config, lib, ... }: {
    imports = [
      disko.nixosModules.disko
      (import ../storage/experiments/disko-fresh-layout.nix {
        device = "/dev/vdb";
        passwordFile = "/run/disko-vm-password";
        espSize = "128M";
        swapSize = "128M";
      })
    ];
    virtualisation.emptyDiskImages = [ 1024 ];
    # Cheap derivation tests only; the installation example keeps the normal
    # cryptsetup KDF defaults for real hardware.
    disko.devices.disk.installation.content.partitions = lib.genAttrs [ "root" "swap" ] (_: {
      content.extraFormatArgs = lib.mkAfter [
        "--pbkdf"
        "pbkdf2"
        "--pbkdf-force-iterations"
        "1000"
      ];
    });
    environment.systemPackages = [
      (import ../lib/python-script.nix { inherit pkgs; } "prepare-disko-fixture"
        ./prepare-disko-fixture.py
        {
          format = config.system.build.formatScript;
          mount = config.system.build.mountScript;
          lsblk = "${pkgs.util-linux}/bin/lsblk";
          findmnt = "${pkgs.util-linux}/bin/findmnt";
          blkid = "${pkgs.util-linux}/bin/blkid";
          umount = "${pkgs.util-linux}/bin/umount";
          mountBin = "${pkgs.util-linux}/bin/mount";
          cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
        }
      )
    ];
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("prepare-disko-fixture")
  '';
}
