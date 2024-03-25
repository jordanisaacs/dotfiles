{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.applications.activitywatch;
  hasWayland = config.jd.graphical.wayland.enable;
in
{
  options.jd.applications.activitywatch.enable = mkEnableOption "activitywatch";

  config = mkIf cfg.enable {
    services.activitywatch = {
      enable = true;
      package = pkgs.aw-server-rust;
      watchers = mkIf hasWayland {
        awatcher.package = pkgs.awatcher;
      };
    };
  };
}
