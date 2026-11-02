{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.jd.graphical.activityMonitor;
  metricsEnabled = cfg.networkMetrics || cfg.cpuEnergyMetrics;
  group = "activity-monitor";
in
{
  options.jd.graphical.activityMonitor = {
    allowedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Users allowed to read optional privileged activity-monitor metrics.";
    };
    networkMetrics = lib.mkEnableOption "NetHogs network metrics for activity monitors";
    cpuEnergyMetrics = lib.mkEnableOption "read-only Intel RAPL energy counters for activity monitors";
  };

  config = lib.mkIf metricsEnabled {
    assertions = [
      {
        assertion = cfg.allowedUsers != [ ];
        message = "Optional activity-monitor metrics require explicit allowedUsers.";
      }
    ];

    users.groups.${group}.members = cfg.allowedUsers;

    # Keep packet capture behind an explicit group. Deliberately omit the
    # upstream setup script's global DAC_READ_SEARCH and SYS_PTRACE bypasses.
    # Other users' protected process descriptors can therefore stay hidden.
    security.wrappers.nethogs = lib.mkIf cfg.networkMetrics {
      source = lib.getExe pkgs.nethogs;
      owner = "root";
      inherit group;
      permissions = "u+rx,g+rx,o-rwx";
      capabilities = "cap_net_admin,cap_net_raw+ep";
    };

    # udev MODE/GROUP target device nodes, not sysfs attributes. Adjust only
    # the energy counter when a RAPL zone appears, using native executables.
    # No writes to power limits, world-readable counters, or sensor probing.
    services.udev.extraRules = lib.mkIf cfg.cpuEnergyMetrics ''
      ACTION=="add", SUBSYSTEM=="powercap", KERNEL=="intel-rapl*", TEST=="energy_uj", RUN+="${pkgs.coreutils}/bin/chgrp ${group} /sys%p/energy_uj", RUN+="${pkgs.coreutils}/bin/chmod 0440 /sys%p/energy_uj"
    '';
  };
}
