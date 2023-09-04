{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.graphical.xorg;
in
{
  options.jd.graphical.xorg = {
    enable = mkOption {
      description = "Enable xserver.";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (config.jd.graphical.enable && cfg.enable) {
    services.xserver = {
      enable = true;
      libinput = {
        enable = true;
        touchpad = {
          naturalScrolling = true;
        };
      };

      displayManager.startx.enable = true;
    };
  };
}
