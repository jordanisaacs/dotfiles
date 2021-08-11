{ pkgs, config, lib, ... }:
{
  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
    };
    grub = {
      enable = true;
      devices = [ "nodev" ];
      efiSupport = true;
      extraEntries = ''
        menuentry "Windows 10" {
          insmod part_gpt
          insmod fat
          insmod search_fs_uuid
          insmod chain
          search --fs-uuid --set=root C2B6-255C
          chainload /EFI/Microsoft/Boot/bootmgfw.efi
        }
      '';
      version = 2;
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
}
