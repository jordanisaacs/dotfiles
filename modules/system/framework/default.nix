{ pkgs, config, lib, ... }:
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
        description = "Enable fingeprint";
        type = types.bool;
        default = false;
      };
    };
  };

  config = mkIf (cfg.enable) (mkMerge [
    ({
      environment.defaultPackages = with pkgs; [ intel-gpu-tools ];
      hardware = {
        video.hidpi.enable = true;
        opengl = {
          enable = true;
          extraPackages = with pkgs; [
            intel-media-driver
            libvdpau-va-gl
          ];
        };
      };

      # wireguard
      networking = {
        nat.enable = true;
        nat.externalInterface = "eth0";
        nat.internalInterfaces = [ "thevoid" ];

        wireguard.interfaces = {
          thevoid = {
            ips = [ "10.55.1.2/16" ];

            privateKeyFile = "/keys/wireguard/private";

            peers = [
              {
                publicKey = "mgDg5mc/60FatP+/pUgHun1e6a7xaiw2wWVEPtjPfGo=";
                allowedIPs = [ "10.55.0.1/32" ];
                endpoint = "172.26.26.90:51820";
              }
            ];
          };
        };
      };


      boot.kernelParams = [ "mem_sleep_default=deep" ];
      # See: https://01.org/linuxgraphics/downloads/firmware
      boot.extraModprobeConfig = ''
        options i915 enable_guc=3
        options i915 enable_fbc=1
      '';
    })
    (mkIf cfg.fprint.enable {
      services.fprintd.enable = true;
    })
  ]);
}
