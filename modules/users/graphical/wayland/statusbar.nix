{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.jd.graphical.wayland;
  systemCfg = config.machineData.systemConfig;
  pythonScript = import ../../../../lib/python-script.nix { inherit pkgs; };
  toggleservice = pythonScript "toggleservice" ../../../../scripts/desktop.py {
    action = "toggle";
    systemctl = "${pkgs.systemd}/bin/systemctl";
  };
  scaled = value: value * cfg.statusbar.scale;
  pixels = value: "${toString (scaled value)}px";
  uiPixels = scaled (config.gtk.font.size * 4 / 3);
  iconPixels = builtins.ceil uiPixels;
  app = command: "${pkgs.uwsm}/bin/uwsm app -t service -- ${command}";
  oxbowStream =
    name:
    pythonScript "oxbow-bar-${name}" ../../../../scripts/waybar-output.py {
      shell = pkgs.runtimeShell;
      script = "${pkgs.oxbow.src}/contrib/waybar/scripts/${name}.sh";
      path = lib.makeBinPath [
        pkgs.oxbow
        pkgs.jq
        pkgs.coreutils
      ];
    };
  riverWaybar = pythonScript "river-waybar" ../../../../scripts/waybar-session.py {
    waybar = "${cfg.statusbar.pkg}/bin/waybar";
    defaultManager = cfg.river.windowManager;
    configurations = {
      oxbow = toString config.xdg.configFile."waybar/config".source;
      reka = toString (
        pkgs.writeText "waybar-reka.json" (
          builtins.toJSON (
            map (
              settings:
              settings
              // {
                # Emacs owns Reka's per-frame tabs. Never run Oxbow subscribers
                # in that session, or invent a second workspace model here.
                modules-left = [ "custom/launcher" ];
              }
            ) config.programs.waybar.settings
          )
        )
      );
    };
    style = "${config.xdg.configHome}/waybar/style.css";
  };
in
{
  options.jd.graphical.wayland.statusbar = {
    enable = lib.mkEnableOption "independent desktop status bar";
    pkg = lib.mkOption {
      type = lib.types.package;
      default = pkgs.waybar;
      description = "Waybar package.";
    };
    outputs = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "Outputs on which to show the bar; empty means every connected output.";
    };
    position = lib.mkOption {
      type = lib.types.enum [
        "top"
        "bottom"
      ];
      default = "bottom";
      description = "Global status bar edge; Reka's workspace tabs stay inside Emacs.";
    };
    scale = lib.mkOption {
      type = lib.types.addCheck lib.types.number (value: value > 0);
      default = 1.0;
      description = "Bar-only scale for UI text, icons and spacing, relative to the shared desktop font.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.statusbar.enable) {
    home.packages = [ pkgs.libappindicator-gtk3 ];
    programs.waybar = {
      enable = true;
      package = cfg.statusbar.pkg;
      systemd.enable = false;
      settings = [
        (
          {
            name = "desktop";
            layer = "top";
            position = cfg.statusbar.position;
            exclusive = true;
            gtk-layer-shell = true;
            spacing = builtins.ceil (scaled 4);
            modules-left = [ "custom/launcher" ];
            modules-center = [ "clock" ];
            modules-right = [
              "privacy"
              "network"
              "pulseaudio"
              "custom/notifications"
              "idle_inhibitor#indicator"
              "power-profiles-daemon"
              "battery"
              # A real SNI tray remains outside the collapsed detail group on
              # every output, including external-only/lid-closed operation.
              "tray"
              "group/details"
            ];

            "custom/launcher" = {
              format = "󰀻";
              tooltip-format = "Applications";
              on-click = "${pkgs.fuzzel}/bin/fuzzel";
            };
            clock = {
              format = "{:%a, %b %d  %I:%M %p}";
              tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
            };
            privacy = {
              icon-size = iconPixels;
              icon-spacing = builtins.ceil (scaled 8);
              transition-duration = 0;
              modules = [
                { type = "screenshare"; }
                { type = "audio-in"; }
              ];
            };
            network = {
              interval = 30;
              interface = systemCfg.networking.wifi.interface or "wl*";
              format-wifi = "{icon}";
              format-ethernet = "󰈀";
              format-linked = "󰲝 No address";
              format-disconnected = "󰤮 Offline";
              format-disabled = "󰤭 Disabled";
              format-icons = [
                "󰤟"
                "󰤢"
                "󰤥"
                "󰤨"
              ];
              tooltip-format-wifi = "{essid} · {signalStrength}%\n{ifname}: {ipaddr}";
              tooltip-format-ethernet = "{ifname}: {ipaddr}";
              tooltip-format-disconnected = "Wi-Fi disconnected · click for Wi-Fi settings";
            }
            // lib.optionalAttrs (systemCfg.networking.wifi.enable or false) {
              on-click = app "${pkgs.wpa_supplicant_gui}/bin/wpa_gui -i ${
                systemCfg.networking.wifi.interface or "wlan0"
              }";
            };
            pulseaudio = {
              format = "{icon} {volume}%";
              format-muted = "󰖁 Muted";
              format-bluetooth = "󰂰 {volume}%";
              format-bluetooth-muted = "󰂲 Muted";
              format-icons.default = [
                "󰕿"
                "󰖀"
                "󰕾"
              ];
              on-click = app "${pkgs.pavucontrol}/bin/pavucontrol";
              on-click-right = "${pkgs.jdScripts.soundTools}/bin/stools vol toggle";
              on-scroll-up = "${pkgs.jdScripts.soundTools}/bin/stools vol up 1";
              on-scroll-down = "${pkgs.jdScripts.soundTools}/bin/stools vol down 1";
              smooth-scrolling-threshold = 5;
            };
            "custom/notifications" = {
              format = "{icon}";
              format-icons = {
                notification = "󱅫";
                none = "󰂜";
                dnd-notification = "󰂠";
                dnd-none = "󰪓";
                inhibited-notification = "󰂛";
                inhibited-none = "󰪑";
                dnd-inhibited-notification = "󰂛";
                dnd-inhibited-none = "󰪑";
              };
              return-type = "json";
              exec = "${config.services.swaync.package}/bin/swaync-client --subscribe-waybar";
              on-click = "${config.services.swaync.package}/bin/swaync-client --toggle-panel --skip-wait";
              on-click-right = "${config.services.swaync.package}/bin/swaync-client --toggle-dnd --skip-wait";
              escape = true;
              tooltip = true;
            };
            "power-profiles-daemon" = {
              format = "{icon}";
              format-icons = {
                default = "󰓅";
                balanced = "󰓅";
                performance = "󱐋";
                power-saver = "󰌪";
              };
              tooltip-format = "Power profile: {profile}\nClick to change profile";
            };
            battery = {
              states = {
                warning = 30;
                critical = 15;
              };
              format = "{icon} {capacity}%";
              format-warning = "{icon} Low · {capacity}%";
              format-critical = "{icon} Low · {capacity}%";
              format-charging = "󰂄 {capacity}%";
              format-plugged = "󰚥 {capacity}%";
              format-icons = [
                "󰂎"
                "󰁺"
                "󰁼"
                "󰁾"
                "󰂀"
                "󰁹"
              ];
              tooltip-format = "{timeTo}";
            };
            tray = {
              icon-size = iconPixels;
              spacing = builtins.ceil (scaled 12);
              show-passive-items = true;
            };

            "group/details" = {
              orientation = "horizontal";
              drawer = {
                transition-duration = 0;
                transition-left-to-right = false;
                click-to-reveal = true;
              };
              modules = [
                "custom/details"
                "backlight"
                "idle_inhibitor"
                "cpu"
                "memory"
                "temperature"
                "mpris"
              ];
            };
            "custom/details" = {
              format = "󰇙";
              tooltip-format = "System details · click to expand or collapse";
            };
            cpu = {
              interval = 10;
              format = "CPU {usage}%";
            };
            memory = {
              interval = 30;
              format = "RAM {used:0.1f}G";
            };
            temperature = {
              format = "{temperatureC}°C";
              critical-threshold = 90;
            };
            backlight = {
              format = "󰃠 {percent}%";
              tooltip-format = "Brightness: {percent}%\nClick: automatic brightness\nRight click: night color";
              on-scroll-up = "${pkgs.brightnessctl}/bin/brightnessctl set +1%";
              on-scroll-down = "${pkgs.brightnessctl}/bin/brightnessctl set 1%-";
              on-click = "${toggleservice}/bin/toggleservice wluma.service";
            }
            // lib.optionalAttrs cfg.screen.gamma.enable {
              on-click-right = "${toggleservice}/bin/toggleservice wlsunset.service";
            };
            idle_inhibitor = {
              format = "{icon}";
              format-icons = {
                activated = "󰅶";
                deactivated = "󰾪";
              };
              tooltip-format-activated = "Idle inhibition active";
              tooltip-format-deactivated = "Idle inhibition off";
            };
            # Native idle-inhibitor instances share one state. Keep the toggle
            # in details and show this second view only while it is active.
            "idle_inhibitor#indicator" = {
              format = "{icon}";
              format-icons = {
                activated = "󰅶";
                deactivated = "";
              };
              tooltip-format-activated = "Idle inhibition active · click to turn off";
            };
            mpris = {
              format = "{status_icon} {dynamic}";
              dynamic-len = 24;
              status-icons = {
                playing = "󰐊";
                paused = "󰏤";
                stopped = "󰓛";
              };
            };
          }
          // lib.optionalAttrs (cfg.statusbar.outputs != [ ]) {
            output = cfg.statusbar.outputs;
          }
          // lib.optionalAttrs (cfg.type == "river") (
            {
              modules-left = [
                "custom/launcher"
              ]
              ++ map (i: "custom/tag#${toString i}") (lib.range 1 9)
              ++ [ "custom/layout" ];
              "custom/layout" = {
                exec = "${oxbowStream "layout"}/bin/oxbow-bar-layout";
                return-type = "json";
                on-click = "${pkgs.oxbow}/bin/oxctl layout next";
              };
            }
            // lib.listToAttrs (
              map (
                i:
                lib.nameValuePair "custom/tag#${toString i}" {
                  # Upstream's event stream hides empty, unselected tags.
                  exec = "${oxbowStream "tag"}/bin/oxbow-bar-tag ${toString i}";
                  return-type = "json";
                  on-click = "${pkgs.oxbow}/bin/oxctl tag view ${toString i}";
                  on-click-right = "${pkgs.oxbow}/bin/oxctl tag toggle ${toString i}";
                }
              ) (lib.range 1 9)
            )
          )
        )
      ];
      style = ''
        @define-color bar_background #19202a;
        @define-color bar_foreground #e7ebf0;
        @define-color bar_muted #a9b3c2;
        @define-color bar_border #343e4e;
        @define-color bar_selection #304362;
        @define-color bar_accent #a8c7fa;
        @define-color bar_warning #ffce83;
        @define-color bar_danger #ffa8a1;

        * {
          font-size: ${toString uiPixels}px;
          font-family: "${config.gtk.font.name}", "Symbols Nerd Font";
          min-height: 0;
          border: none;
          border-radius: 0;
          box-shadow: none;
          text-shadow: none;
        }
        window#waybar {
          background: @bar_background;
          color: @bar_foreground;
        }
        window#waybar.bottom { border-top: 1px solid @bar_border; }
        window#waybar.top { border-bottom: 1px solid @bar_border; }
        .modules-left, .modules-right { margin: ${pixels 4} ${pixels 10}; }
        .module { padding: ${pixels 4} ${pixels 8}; border-radius: ${pixels 7}; }
        #clock { padding: ${pixels 6} ${pixels 12}; }
        #custom-launcher { color: @bar_accent; padding: ${pixels 4} ${pixels 10}; }
        #custom-tag { color: @bar_muted; min-width: ${pixels 20}; }
        #custom-tag.viewed { background: @bar_selection; color: @bar_accent; }
        #custom-tag.urgent { color: @bar_warning; }
        #custom-layout { color: @bar_muted; }
        #privacy-item { color: @bar_danger; }
        #custom-notifications.notification { color: @bar_accent; }
        #custom-notifications.dnd-notification, #custom-notifications.dnd-none,
        #custom-notifications.dnd-inhibited-notification, #custom-notifications.dnd-inhibited-none {
          color: @bar_warning;
        }
        #network.disconnected, #network.disabled, #network.linked,
        #battery.warning, #power-profiles-daemon.power-saver { color: @bar_warning; }
        #battery.critical, #temperature.critical { color: @bar_danger; }
        #pulseaudio.muted { color: @bar_muted; }
        #idle_inhibitor.deactivated { color: @bar_muted; }
        #idle_inhibitor.activated { background: @bar_selection; color: @bar_warning; }
        #idle_inhibitor.indicator.deactivated { padding: 0; margin: 0; min-width: 0; }
        #power-profiles-daemon.performance { color: @bar_accent; }
        #tray { padding: ${pixels 4} ${pixels 10}; }
        #tray > .needs-attention { background: @bar_selection; border-radius: ${pixels 7}; }
        #custom-details { color: @bar_muted; min-width: ${pixels 18}; }
        #details { border-radius: ${pixels 7}; }
        #details:hover { background: @bar_selection; }
        .drawer-child { color: @bar_muted; }
        tooltip, menu {
          background: @bar_background;
          color: @bar_foreground;
          border: 1px solid @bar_border;
          border-radius: ${pixels 8};
        }
        tooltip label { padding: ${pixels 6}; }
        menuitem { padding: ${pixels 6} ${pixels 10}; }
        menuitem:hover { background: @bar_selection; }
      '';
    };

    systemd.user.services.waybar = {
      Unit = {
        Description = "Desktop status bar and system tray";
        Documentation = "https://github.com/Alexays/Waybar/wiki";
        BindsTo = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
        Wants = [ "tray.target" ];
        Before = [ "tray.target" ];
      };
      Service = {
        ExecStart =
          if cfg.type == "river" then
            "${riverWaybar}/bin/river-waybar"
          else
            "${cfg.statusbar.pkg}/bin/waybar";
        ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR2 $MAINPID";
        Restart = "on-failure";
        KillMode = "mixed";
        Slice = "session-graphical.slice";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
