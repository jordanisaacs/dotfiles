{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.applications.syncthing;
  isGraphical = let
    graphical = config.jd.graphical;
  in
    graphical.xorg.enable == true || graphical.wayland.enable == true;
in {
  options.jd.applications.syncthing = {
    enable = mkOption {
      description = "Enable syncthing";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (config.jd.applications.enable && cfg.enable) {
    services.syncthing = {
      enable = true;
      tray.enable = isGraphical;
    };
  };
}
