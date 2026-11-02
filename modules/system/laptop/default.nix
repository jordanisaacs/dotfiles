{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.jd.laptop;
  cpuPolicy = pkgs.writers.writePython3Bin "laptop-cpu-policy" { flakeIgnore = [ "E501" ]; } (
    builtins.readFile ./cpu_policy.py
  );
in
{
  options.jd.laptop.enable = lib.mkEnableOption "automatic laptop power and performance management";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      brightnessctl
      powertop
    ];

    # A single policy owner handles CPU, PCIe, storage and USB power saving.
    # TLP responds to power-source changes and resume; tlp-pd exposes the
    # standard desktop profile API without another daemon changing tunables.
    services = {
      auto-cpufreq.enable = false;

      power-profiles-daemon.enable = false;

      tuned.enable = false;

      tlp = {
        enable = true;
        # nixpkgs' aggregate install-man target also installs tlp-pd's manuals.
        # Give each package its own upstream install target to avoid collisions.
        package =
          (pkgs.tlp.override {
            enableRDW = config.networking.networkmanager.enable;
          }).overrideAttrs
            (old: {
              installTargets = map (
                target: if target == "install-man" then "install-man-tlp" else target
              ) old.installTargets;
            });
        pd = {
          enable = true;
          package = pkgs.tlp-pd.override { tlp = config.services.tlp.package; };
        };
        settings = {
          TLP_AUTO_SWITCH = 1;
          TLP_PROFILE_AC = "PRF";
          TLP_PROFILE_BAT = "BAL";

          # Hardware-managed P-states still react to workload. Drivers without
          # EPP ignore these preferences; their kernel governor stays in charge.
          CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
          CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_power";
          CPU_ENERGY_PERF_POLICY_ON_SAV = "power";
          CPU_BOOST_ON_AC = 1;
          CPU_BOOST_ON_BAT = 1;
        };
      };

      # UPower observes the system battery regardless of its kernel device name.
      upower = {
        enable = true;
        usePercentageForPolicy = true;
        percentageLow = 15;
        percentageCritical = 7;
        percentageAction = 5;
        criticalPowerAction = "Hibernate";
      };

      logind.settings.Login = {
        HandleLidSwitch = "suspend-then-hibernate";
        HandleLidSwitchExternalPower = "suspend";
        HandleLidSwitchDocked = "ignore";
        HandlePowerKey = "suspend-then-hibernate";
        IdleAction = "suspend-then-hibernate";
        IdleActionSec = "15min";
      };
    };
    powerManagement.powertop.enable = false;

    systemd.services.tlp.serviceConfig.ExecStartPre = [
      "${cpuPolicy}/bin/laptop-cpu-policy"
    ];

    # Keep the encrypted-swap hibernation policy without forcing a particular
    # firmware sleep state or maintaining a parallel ACPI event handler.
    systemd.sleep.settings.Sleep.HibernateDelaySec = "1h";
  };
}
