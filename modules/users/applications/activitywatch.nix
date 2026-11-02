{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.applications.activitywatch;
  hasWayland = config.jd.graphical.wayland.enable;
in
{
  options.jd.applications.activitywatch.enable = mkEnableOption "activitywatch";

  config = mkIf cfg.enable {
    services.activitywatch = {
      enable = true;
      package = pkgs.aw-server-rust;
      watchers = mkIf hasWayland { awatcher.package = pkgs.awatcher; };
    };

    # awatcher should start and stop depending on graphical-session.target
    # starting activitywatch should only start awatcher if graphical-session.target is active
    systemd.user.services.activitywatch-watcher-awatcher = mkIf hasWayland {
      Unit = {
        After = [ "graphical-session.target" ];
        Requisite = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Install = {
        # Override the upstream activitywatch.target autostart: the server may
        # run at login, but its Wayland watcher needs a ready desktop first.
        WantedBy = mkForce [ "graphical-session.target" ];
      };
    };
  };
}
