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
      type = types.enum ["efi" "bios"];
    };

    grubDevice = mkOption {
      description = "Grub device";
      default = null;
      type = types.str;
    };
  };

  config = mkMerge [
    (mkIf (cfg.type == "efi") {
      boot = {
        loader = {
          efi = {
            efiSysMountPoint = "/boot";
          };

          grub = {
            enable = true;
            devices = ["nodev"];
            efiSupport = true;
            useOSProber = true;
            version = 2;
            extraEntries = ''
              menuentry "Reboot" {
                reboot
              }
              menuentry "Power off" {
                halt
              }
            '';
            extraConfig =
              if (config.jd.framework.enable)
              then "i915.enable_psr=0"
              else "";
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
