{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.jd.applications.activitywatch;
  hasWayland = config.jd.graphical.wayland.enable;
in {
  options.jd.applications.activitywatch.enable = mkEnableOption "activitywatch";

  config = mkIf cfg.enable {
    services.activitywatch = {
      enable = true;
      package = pkgs.aw-server-rust;
      watchers = mkIf hasWayland { awatcher.package = pkgs.awatcher; };
    };

    # awatcher should start and stop depending on wayland-session.target
    # starting activitywatch should only start awatcher if wayland-session.target is active
    systemd.user.services.activitywatch-watcher-awatcher = {
      Unit = {
        After = [ "wayland-session.target" ];
        Requisite = [ "wayland-session.target" ];
        PartOf = [ "wayland-session.target" ];
      };
      Install = { WantedBy = [ "wayland-session.target" ]; };
    };
  };
}
