{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.laptop;
  brightnessScript = pkgs.writeShellScript "auto-brightness" ''
    adjust=3
    sensitivity=$(($(cat /sys/class/backlight/intel_backlight/max_brightness)/20))
    max=
    min=20
    delay=2
    while :; do
        updated=1
        while [ $updated -gt 0 ]; do
            if [ -n "$(${pkgs.acpi}/bin/acpi -a | ${pkgs.gnugrep}/bin/grep off-line)" ]; then
                max=50
            else
                max=100
            fi

            updated=0
            backlight=$(cat /sys/class/backlight/intel_backlight/brightness)
            sensor=$(cat /sys/bus/iio/devices/iio:device0/in_illuminance_raw)
            target=$(printf '%.0f' "$(${pkgs.light}/bin/light -G)")
            if [ $backlight -gt $sensor ]; then
                if [ $(($backlight - $sensor)) -gt $sensitivity ]; then
                    if [ $target -eq $min ]; then
                        break
                    fi
                    updated=1
                    target=$(($target - $adjust))
                fi
            fi
            if [ $backlight -lt $sensor ]; then
                if [ $(($backlight - $sensor)) -lt $sensitivity ]; then
                    if [ $target -eq $max ]; then
                        break
                    fi
                    updated=1
                    target=$(($target + $adjust))
                fi
            fi
            if [ $target -gt $max ]; then
                target=$max
            fi
            if [ $target -lt $min ]; then
                target=$min
            fi
            if [ $updated -gt 0 ]; then
                echo “Setting brightness: $target”
                echo “Backlight brightness: $backlight”
                echo “Ambient light: $sensor”
                echo “Adjusted brightness: $target”
                echo "-------"
                ${pkgs.light}/bin/light -S $target
            fi
        done

        sleep $delay
    done
  '';
in
{
  options.jd.laptop = {
    enable = mkEnableOption "Laptop settings. Also tags as laptop for user settings.";

    manager = mkOption {
      type = types.enum [
        "tlp"
        "auto-cpufreq"
      ];
      description = "Whether this wireguard interface has a dns server, should be a client of the dns servers, or nothing";
      default = "auto-cpufreq";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      environment.systemPackages = with pkgs; [
        acpid
        powertop
      ];

      programs = {
        light.enable = true;
      };

      systemd = {
        # Replace suspend mode with hybrid-sleep. So can do hybrid-sleep then hibernate
        # hybrid-sleep broken on framework: https://community.frame.work/t/issues-with-sleep-states-on-linux/7363
        # Framework: cat /sys/power/mem_sleep -> [s2idle] deep
        # Change suspendstate to deep for framework
        sleep.extraConfig = ''
          HibernateDelaySec=1h
        '';

        user.services."autobrightness" = {
          wantedBy = [ "default.target" ];

          unitConfig = {
            Description = "Automatic brightness adjustment";
          };

          serviceConfig = {
            ExecStart = brightnessScript;
            Restart = "on-failure";
            RestartSec = 30;
            StartLimitInterval = 350;
            StartLimitBurst = 10;
          };
        };
      };

      # https://man.archlinux.org/man/systemd-sleep.conf.5
      # https://www.kernel.org/doc/html/latest/admin-guide/pm/sleep-states.html
      # Suspend mode -> Hybrid-Sleep. This enables hybrid-sleep then hibernate
      services = {
        # Hibernate on low battery. from: https://wiki.archlinux.org/title/laptop#Hibernate_on_low_battery_level
        udev.extraRules = ''
          # Suspend the system when battery level drops to 5% or lower
          SUBSYSTEM=="power_supply", ATTR{status}=="Discharging", ATTR{capacity}=="[0-5]", RUN+="${pkgs.systemd}/bin/systemctl hibernate"
        '';

        logind = {
          # idleaction with startx: https://bbs.archlinux.org/viewtopic.php?id=207536
          # <LeftMouse>https://wiki.archlinux.org/title/Power_management
          # Options: ttps://www.freedesktop.org/software/systemd/man/logind.conf.html
          settings = {
            Login = {
              HandleLidSwitch = "suspend-then-hibernate";
              HandleLidSwitchExternalPower = "suspend-then-hibernate";
              HandleLidSwitchDocked = "ignore";
              HandlePowerKey = "suspend-then-hibernate";
              IdleAction = "suspend-then-hibernate";
              IdleActionSec = "5min";
            };
          };
        };

        acpid = {
          # NixOS source: https://github.com/NixOS/nixpkgs/blob/nixos-21.05/nixos/modules/services/hardware/acpid.nix
          # acpid info: https://wiki.archlinux.org/title/acpid
          enable = true;
          handlers = {
            # Volume not controllable from acpid as pulseaudio is user service and acpid is system
            brightness-down = {
              event = "video/brightnessdown*";
              action = "${pkgs.light}/bin/light -U 4";
            };
            brightness-up = {
              event = "video/brightnessup";
              action = "${pkgs.light}/bin/light -A 4";
            };
            # ac-power = {
            #   event = "ac_adapter/*";
            #   action = ''
            #     vals=($1)  # space separated string to array of multiple values
            #     case ''${vals[3]} in
            #       00000000)
            #         max_bright=30
            #         curr_bright=$(echo $(${pkgs.light}/bin/light -G) | xargs printf "%0.f")
            #         ${pkgs.light}/bin/light -S $((curr_bright<max_bright ? curr_bright : max_bright))
            #         ;;
            #       00000001)
            #         ${pkgs.light}/bin/light -S 100
            #         ;;
            #     esac
            #   '';
            # };
          };
        };
      };
    }
    (mkIf (cfg.manager == "auto-cpufreq") {
      services.auto-cpufreq.enable = true;
    })
    (mkIf (cfg.manager == "tlp") {
      services.tlp = {
        # Nix source: https://github.com/NixOS/nixpkgs/blob/nixos-21.05/nixos/modules/services/hardware/tlp.nix
        # TLP settings: https://linrunner.de/tlp/settings/index.html
        enable = false;
        settings = {
          "SOUND_POWER_SAVE_ON_AC" = 0;
          "SOUND_POWER_SAVE_ON_BAT" = 1;
          "SOUND_POWER_SAVE_CONTROLLER" = "Y";
          "DISK_APM_LEVEL_ON_AC" = "254 254";
          "DISK_APM_LEVEL_ON_BAT" = "128 128";
          "DISK_IOSCHED" = "mq-deadline mq-deadline";
          "SATA_LINKPWR_ON_AC" = "med_power_with_dipm max_performance";
          "SATA_LINKPWR_ON_BAT" = "min_power min_power";
          "MAX_LOST_WORK_SECS_ON_AC" = 15;
          "MAX_LOST_WORK_SECS_ON_BAT" = 60;
          "NMI_WATCHDOG" = 0;
          "WIFI_PWR_ON_AC" = "off";
          "WIFI_PWR_ON_BAT" = "on";
          "WOL_DISABLE" = "Y";
          "CPU_SCALING_GOVERNOR_ON_AC" = "powersave";
          "CPU_SCALING_GOVERNOR_ON_BAT" = "powersave";
          "CPU_MIN_PERF_ON_AC" = 0;
          "CPU_MAX_PERF_ON_AC" = 100;
          "CPU_MIN_PERF_ON_BAT" = 0;
          "CPU_MAX_PERF_ON_BAT" = 50;
          "CPU_BOOST_ON_AC" = 1;
          "CPU_BOOST_ON_BAT" = 1;
          "SCHED_POWERSAVE_ON_AC" = 0;
          "SCHED_POWERSAVE_ON_BAT" = 1;
          "RESTORE_DEVICE_STATE_ON_STARTUP" = 0;
          "RUNTIME_PM_ON_AC" = "on";
          "RUNTIME_PM_ON_BAT" = "auto";
          "PCIE_ASPM_ON_AC" = "default";
          "PCIE_ASPM_ON_BAT" = "powersupersave";
          "USB_AUTOSUSPEND" = 0;
        }
        // (
          if config.jd.framework.enable then
            {
              "CPU_ENERGY_PERF_POLICY_ON_AC" = "performance";
              "CPU_ENERGY_PERF_POLICY_ON_BAT" = "power";
              "PLATFORM_PROFILE_ON_AC" = "performance";
              "PLATFORM_PROFILE_ON_BAT" = "power";
              "CPU_HWP_DYN_BOOST_ON_AC" = 1;
              "CPU_HWP_DYN_BOOST_ON_BAT" = 0;
              "INTEL_GPU_MIN_FREQ_ON_AC" = 100;
              "INTEL_GPU_MAX_FREQ_ON_AC" = 1300;
              "INTEL_GPU_BOOST_FREQ_ON_AC" = 1300;
              "INTEL_GPU_MIN_FREQ_ON_BAT" = 100;
              "INTEL_GPU_MAX_FREQ_ON_BAT" = 800;
              "INTEL_GPU_BOOST_FREQ_ON_BAT" = 1000;
            }
          else
            { }
        );
      };
    })
  ]);
}
