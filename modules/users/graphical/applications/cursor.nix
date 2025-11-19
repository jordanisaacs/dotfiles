{ pkgs, config, lib, ... }:
with lib;
let 
  cfg = config.jd.graphical.applications.cursor;
in {
  options.jd.graphical.applications.cursor = {
    enable = mkEnableOption "Cursor editor with Wayland and scaling support";
    
    scale = mkOption {
      type = types.str;
      default = "1.5";
      description = "Device scale factor for Cursor";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      (pkgs.symlinkJoin {
        name = "cursor-wayland";
        paths = [ pkgs.code-cursor ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/cursor \
            --add-flags "--force-device-scale-factor=${cfg.scale}"
        '';
      })
    ];
  };
}