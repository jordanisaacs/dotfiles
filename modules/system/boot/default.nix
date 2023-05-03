{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.boot;
in {
  options.jd.boot = {
    type = mkOption {
      description = "Type of boot. Default encrypted-efi";
      default = null;
      type = types.enum ["uefi" "bios"];
    };

    grubDevice = mkOption {
      description = "Grub device";
      default = null;
      type = types.str;
    };

    modules = mkOption {
      description = "List of initrd modules";
      default = [];
      type = with types; listOf package;
    };
  };

  config = mkMerge [
    (mkIf (cfg.type == "uefi") {
      boot = {
        initrd.systemd.enable = true;
        loader = {
          efi = {
            efiSysMountPoint = "/boot";
            canTouchEfiVariables = true;
          };

          systemd-boot = {
            enable = true;
            editor = false;
            extraEntries = {
              # Sorting is from z-a so go after nixos entries
              "power.conf" = ''
                title Power Off
                efi /efi/efi-power/poweroff.efi
              '';
              # n*** - where nixos entries are
              "a-reboot.conf" = ''
                title Reboot
                efi /efi/efi-power/reboot.efi
              '';
            };
            extraFiles = {
              "efi/efi-power/reboot.efi" = "${pkgs.efi-power}/reboot.efi";
              "efi/efi-power/poweroff.efi" = "${pkgs.efi-power}/poweroff.efi";
            };
          };
        };
      };
    })
    (mkIf (cfg.type == "bios") {
      boot = {
        loader = {
          grub = {
            enable = true;
            version = 2;
            device = cfg.grubDevice;
            efiSupport = false;
          };
        };
      };
    })
  ];
}
