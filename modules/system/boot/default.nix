{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.boot;
in {
  options.jd.boot = mkOption {
    description = "Type of boot. Default encrypted-efi";
    default = null;
    type = types.enum [ "encrypted-efi" ];
  };

  config = mkIf (cfg == "encrypted-efi") {
    boot.loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };

      grub = {
        enable = true;
        devices = [ "nodev" ];
        efiSupport = true;
        useOSProber = true;
        version = 2;
        extraEntries = ''
          menuentry "Reboot" {
            reboot
          }
          menuEntry "Power off" {
            halt
          }
        '';
      };
    };

    boot.initrd.luks.devices = {
      cryptkey = {
        device = "/dev/disk/by-label/NIXKEY";
      };

      cryptroot = {
        device = "/dev/disk/by-label/NIXROOT";
        keyFile = "/dev/mapper/cryptkey";
      };

      cryptswap = {
        device = "/dev/disk/by-label/NIXSWAP";
        keyFile = "/dev/mapper/cryptkey";
      };
    };

    fileSystems."/" = {
      device = "/dev/disk/by-label/DECRYPTNIXROOT";
      fsType = "ext4";
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-label/BOOT";
      fsType = "vfat";
    };

    swapDevices = [
      { device = "/dev/disk/by-label/DECRYPTNIXSWAP"; }
    ];
  };
}
