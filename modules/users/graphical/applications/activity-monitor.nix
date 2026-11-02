{
  config,
  lib,
  pkgs,
  ...
}:
let
  metrics = config.machineData.systemConfig.graphical.activityMonitor or { };
  managedMetrics =
    (metrics.networkMetrics or false)
    && (metrics.cpuEnergyMetrics or false)
    && builtins.elem config.home.username (metrics.allowedUsers or [ ]);
in
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
    }
    // lib.optionalAttrs managedMetrics {
      # The native system configuration owns these setup choices. The app's
      # root script would widen access and imperatively probe sensor buses.
      first-time-running = false;
    };
  };
}
