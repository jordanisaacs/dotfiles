{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.jd.framework;
in {
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
      hardware.video.hidpi.enable = true;
    })
    (mkIf cfg.fprint.enable {
      services.fprintd.enable = true;
    })
  ]);
}
