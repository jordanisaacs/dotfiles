{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.framework;
in
{
  options.jd.framework = {
    enable = mkOption {
      description = "Enable framework options";
      type = types.bool;
      default = false;
    };

    fprint = {
      enable = mkOption {
        description = "Enable fingerprint";
        type = types.bool;
        default = false;
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      hardware.cpu.intel.updateMicrocode = true;
      hardware.sensor.iio.enable = true;

      services = {
        fstrim = {
          enable = true;
          interval = "weekly";
        };

        # https://community.frame.work/t/headphone-jack-intermittent-noise/5246/90
        acpid = {
          enable = true;
          handlers = {
            headphone-power-save-off = {
              event = "jack/headphone HEADPHONE plug";
              action = "echo 0 >/sys/module/snd_hda_intel/parameters/power_save";
            };
            headphone-power-save-on = {
              event = "jack/headphone HEADPHONE unplug";
              action = "echo 1 >/sys/module/snd_hda_intel/parameters/power_save";
            };
          };
        };

        thermald.enable = true;
      };

      boot = {
        kernelParams = [
          # Current kernels use their default sleep mode; s2idle's old
          # Framework regression was fixed by 6.8 (nixos-hardware).
          # https://community.frame.work/t/linux-battery-life-tuning/6665/156
          "nvme.noacpi=1"
        ];

        # The dell-headset-multi quirk is only needed before Linux 6.6.8.
        # https://github.com/NixOS/nixos-hardware/blob/master/framework/13-inch/common/default.nix
      };
    }
    (mkIf cfg.fprint.enable { services.fprintd.enable = true; })
    (mkIf config.jd.graphical.enable {
      boot.initrd.kernelModules = [ "i915" ];

      environment.defaultPackages = with pkgs; [
        intel-gpu-tools
        vulkan-validation-layers
        vulkan-tools
      ];
      hardware = {
        graphics = {
          enable = true;
          enable32Bit = true;
          extraPackages = with pkgs; [
            intel-media-driver
            libvdpau-va-gl
            intel-vaapi-driver
          ];
        };
      };
    })
  ]);
}
