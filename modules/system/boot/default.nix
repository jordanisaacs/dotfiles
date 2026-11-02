{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.boot;
in
{
  options.jd.boot = {
    type = mkOption {
      description = "Type of boot. Default encrypted-efi";
      default = null;
      type = types.enum [
        "uefi"
        "bios"
      ];
    };

    grubDevice = mkOption {
      description = "Grub device";
      default = null;
      type = types.str;
    };

    modules = mkOption {
      description = "List of initrd modules";
      default = [ ];
      type = with types; listOf package;
    };
  };

  config = mkMerge [
    (mkIf (cfg.type == "uefi") {
      boot = {
        loader = {
          efi = {
            efiSysMountPoint = "/boot";
            canTouchEfiVariables = true;
          };

          systemd-boot = {
            enable = true;
            editor = false;
            configurationLimit = 15;
            # systemd-boot supports Shift+O (power off) and Shift+B (reboot).
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
