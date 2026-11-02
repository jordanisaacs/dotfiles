{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.jd.graphical.applications.enable {
    # No dedicated upstream Home Manager module exists. The native desktop
    # entry inherits Fuzzel's UWSM launch path and starts its helper on demand.
    home.packages = [ pkgs.mission-center ];

    dconf.settings."io/missioncenter/MissionCenter" = {
      window-selected-page = "apps-page";
      window-interface-style = "system";
      apps-page-merged-process-stats = true;
      # The current key is uint64 in units of 50 ms; the old int is deprecated.
      app-update-interval-u64 = lib.hm.gvariant.mkUint64 40;
    };
  };
}
