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

        # Match nixos-hardware's Tiger Lake headphone-noise workaround. Keep
        # the MEI device awake while TLP owns the HDA codec's power policy.
        # https://github.com/NixOS/nixos-hardware/blob/master/framework/13-inch/common/intel.nix
        udev.extraRules = ''
          SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0xa0e0", ATTR{power/control}="on"
        '';

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

      environment.systemPackages = with pkgs; [
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
          ];
          extraPackages32 = [ pkgs.driversi686Linux.intel-media-driver ];
        };
      };
    })
  ]);
}
