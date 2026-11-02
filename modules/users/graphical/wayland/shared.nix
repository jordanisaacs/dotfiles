{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.graphical.wayland;
  systemCfg = config.machineData.systemConfig;
  isLaptop = systemCfg.laptop.enable or false;
  pythonScript = import ../../../../lib/python-script.nix { inherit pkgs; };
  toggleservice = pythonScript "toggleservice" ../../../../scripts/desktop.py {
    action = "toggle";
    systemctl = "${pkgs.systemd}/bin/systemctl";
  };

  locs = {
    pittsburgh = {
      latitude = "40.4";
      longitude = "-80";
    };
    seattle = {
      latitude = "47.6";
      longitude = "-122.3";
    };
  };
in
{
  options.jd.graphical.wayland = {
    enable = mkOption {
      type = types.bool;
      description = "Enable wayland";
    };

    background = {
      enable = mkOption {
        type = types.bool;
        description = "Enable background [swaybg]";
      };

      pkg = mkOption {
        type = types.package;
        description = "Package to use for swaybg";
      };

      image = mkOption {
        type = types.path;
        description = "Path to image file used for background";
      };

      mode = mkOption {
        type = types.enum [
          "stretch"
          "fill"
          "fit"
          "center"
          "tile"
        ];
        description = "Scaling mode for background";
      };
    };

    screenlock = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable screen locking, must enable it on system as well for pam.d (waylock)";
      };

      type = mkOption {
        type = types.enum [
          "waylock"
          "swaylock"
        ];
        default = "waylock";
        description = "Which screen locking software to use";
      };

      timeout = mkOption {
        type = types.int;
        default = 180;
        description = "Timeout for locking the screen";
      };
    };

    statusbar = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable status bar [waybar]";
      };

      pkg = mkOption {
        type = types.package;
        default = pkgs.waybar;
        description = "Waybar package";
      };
    };

    screen = {
      gamma = {
        enable = mkEnableOption "screen gamma control";
        loc = mkOption {
          type = with types; enum (attrNames locs);
          default = "pittsburgh";
          description = "gamma control location";
        };
      };
    };

    terminal = {
      theme = mkOption {
        type =
          with types;
          enum [
            "tokyo-night"
            "dracula"
          ];
        description = "Terminal color theme";
        default = "tokyo-night";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      home.sessionVariables = {
        QT_QPA_PLATFORM = "wayland";
      };

      home.packages = with pkgs; [
        wl-clipboard
        wlr-randr
        wdisplays
        wev
        grim
        slurp
      ];

      xdg.portal = {
        enable = true;
        extraPortals = [
          pkgs.xdg-desktop-portal-wlr
          pkgs.xdg-desktop-portal-gtk
        ];
        config.${cfg.type}.default = [
          "wlr"
          "gtk"
        ];
      };

      xdg.mimeApps = {
        associations.added = {
          "x-scheme-handler/terminal" = "com.mitchellh.ghostty.desktop";
        };

        defaultApplications = {
          "x-scheme-handler/terminal" = "com.mitchellh.ghostty.desktop";
        };
      };

      programs.ghostty = {
        enable = true;
        settings = {
          font-family = [
            "Berkeley Mono Variable"
            "Noto Color Emoji"
          ];
          # Preserve the terminal size independently of GUI typography changes.
          font-size = 20;
          theme = if cfg.terminal.theme == "tokyo-night" then "TokyoNight" else "Dracula";
          window-padding-x = 2;
          window-padding-y = 2;
          window-decoration = false;
        };
      };

      services.mako.enable = true;
      services.polkit-gnome.enable = true;
    }
    (mkIf cfg.screenlock.enable (
      let
        isWaylock = cfg.screenlock.type == "waylock";
        isSwaylock = cfg.screenlock.type == "swaylock";
      in
      {
        assertions = [
          {
            assertion = isWaylock -> (systemCfg.graphical.wayland.waylockPam && isWaylock);
            message = "Waylock PAM must be enabled by the system to use waylock screen locking.";
          }

          {
            assertion = isSwaylock -> (systemCfg.graphical.wayland.swaylockPam && isSwaylock);
            message = "Swaylock PAM must be enabled by the system to use waylock screen locking.";
          }
        ];

        services.swayidle =
          let
            lockCommand =
              if cfg.screenlock.type == "waylock" then
                "${pkgs.waylock}/bin/waylock -fork-on-lock"
              else
                "${pkgs.swaylock}/bin/swaylock -f";
          in
          {
            enable = true;
            timeouts = [
              {
                inherit (cfg.screenlock) timeout;
                command = lockCommand;
              }
            ];
            # Soemtimes wlr-randr fails to turn screen back on, comment out for now
            # ++ optional isLaptop {
            #   timeout = 60;
            #   command = "${pkgs.wlr-randr}/bin/wlr-randr --output eDP-1 --off";
            #   resumeCommand = "${pkgs.wlr-randr}/bin/wlr-randr --output eDP-1 --on";
            # };

            events.before-sleep = lockCommand;
            systemdTargets = [ "graphical-session.target" ];
            extraArgs = [
              "-w"
              "idlehint"
              "600"
            ];
          };

        home.packages =
          with pkgs;
          (optional (cfg.screenlock.type == "waylock") waylock)
          ++ (optional (cfg.screenlock.type == "swaylock") swaylock);
      }
    ))
    (mkIf cfg.background.enable {
      home.packages = [ pkgs.swaybg ];

      systemd.user.services.swaybg = mkIf cfg.background.enable {
        Unit = {
          Description = "swaybg background service";
          Documentation = [ "man:swaybg(1)" ];
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
          Before = mkIf cfg.statusbar.enable [ "waybar.service" ];
        };

        Service = {
          ExecStart = "${cfg.background.pkg}/bin/swaybg --image ${cfg.background.image} --mode ${cfg.background.mode}";
          Restart = "on-failure";
          Slice = "background-graphical.slice";
        };

        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };
    })
    (mkIf cfg.statusbar.enable {
      home.packages = [ pkgs.libappindicator-gtk3 ];
      programs.waybar =
        let
          primaryDisplay = if isLaptop then "eDP-1" else "DP-1";

        in
        {
          enable = true;
          package = cfg.statusbar.pkg;
          settings = [
            (mkMerge [
              {
                layer = "bottom";
                output = [ primaryDisplay ];

                modules-center = [ "clock" ];
                modules-right = [
                  "cpu"
                  "memory"
                  "temperature"
                  "battery"
                  "power-profiles-daemon"
                  "backlight"
                  "custom/media"
                  "pulseaudio"
                  "network"
                  "idle_inhibitor"
                  "tray"
                ];

                gtk-layer-shell = true;
                clock = {
                  format = "{:%I:%M %p}";
                  tooltip = true;
                  tooltip-format = ''
                    <big>{:%Y %B}</big>
                    <tt><small>{calendar}</small></tt>'';
                };
                cpu = {
                  interval = 10;
                  format = "{usage}% ";
                  tooltip = true;
                };
                memory = {
                  interval = 30;
                  format = "{used:0.1f}G/{total:0.1f}G ";
                  tooltip = true;
                };
                temperature = { };
                "power-profiles-daemon" = {
                  format = "{icon}";
                  format-icons = {
                    default = "";
                    performance = "";
                    balanced = "";
                    power-saver = "";
                  };
                };
                battery = {
                  states = {
                    good = 80;
                    warning = 30;
                    critical = 15;
                  };
                  format = "{capacity}% {icon}";
                  format-charging = "{capacity}% 󱎗";
                  format-plugged = "{capacity}% ";
                  format-alt = "{time} {icon}";
                  format-icons = [
                    ""
                    ""
                    ""
                    ""
                    ""
                  ];
                  tooltip = true;
                  tooltip-format = "{timeTo}";
                };
                backlight = {
                  format = "{percent}% {icon}";
                  format-icons = [
                    ""
                    ""
                  ];
                  on-scroll-up = "${pkgs.brightnessctl}/bin/brightnessctl set +1%";
                  on-scroll-down = "${pkgs.brightnessctl}/bin/brightnessctl set 1%-";
                  on-click = "${toggleservice}/bin/toggleservice wluma.service";
                }
                // (optionalAttrs cfg.screen.gamma.enable {
                  on-click-right = "${toggleservice}/bin/toggleservice wlsunset.service";
                });
                pulseaudio = {
                  format = "{volume}% {icon} {format_source}";
                  format-bluetooth = "{volume}% {icon} {format_source}";
                  format-bluetooth-muted = "{volume}%  {format_source}";
                  format-muted = "{volume}%  {format_source}";
                  format-source = "{volume}% ";
                  format-source-muted = "{volume}% ";
                  format-icons = {
                    "default" = [
                      ""
                      ""
                      ""
                    ];
                  };
                  on-scroll-up = "${pkgs.jdScripts.soundTools}/bin/stools vol up 1";
                  on-scroll-down = "${pkgs.jdScripts.soundTools}/bin/stools vol down 1";
                  on-click-right = "${pkgs.jdScripts.soundTools}/bin/stools vol toggle";
                  on-click = "${pkgs.uwsm}/bin/uwsm app -t service -- ${pkgs.pavucontrol}/bin/pavucontrol";
                  tooltip = true;
                };
                network = {
                  interval = 60;
                  interface = systemCfg.networking.wifi.interface or "wl*";
                  format-icons = {
                    wifi = [
                      "󰤟"
                      "󰤢"
                      "󰤨"
                    ];
                    ethernet = [ "󰈀" ];
                    disconnected = [ "" ];
                    disabled = [ "󰲜" ];
                    linked = [ "󰲝" ];
                  };
                  format = "{ifname}";
                  format-wifi = "{essid} {icon}";
                  format-ethernet = "{ipaddr}/{cidr} {icon}";
                  format-linked = "{ifname}: (No IP) {icon} ";
                  format-disconnected = "Disconnected {icon}";
                  format-disabled = "Disabled {icon}";
                  format-alt = "{ifname}: {ipaddr}/{cidr}";
                  tooltip = true;
                  tooltip-format = "{ifname} via {gwaddr}: {bandwidthUpBytes} 󰳘 {bandwidthDownBytes} 󰱦";
                };
                idle_inhibitor = {
                  format = "{icon}";
                  format-icons = {
                    activated = "";
                    deactivated = "";
                  };
                };
                tray = {
                  spacing = 10;
                };
                "custom/media" = {
                  format = "{icon}{}";
                  return-type = "json";
                  format-icons = {
                    Playing = " ";
                    Paused = " ";
                  };
                  max-length = 30;
                  exec = ''${pkgs.playerctl}/bin/playerctl -a metadata --format '{"text": "{{playerName}}: {{artist}} - {{markup_escape(title)}}", "tooltip": "{{playerName}} : {{markup_escape(title)}}", "alt": "{{status}}", "class": "{{status}}"}' -F'';
                  on-click = "${pkgs.playerctl}/bin/playerctl play-pause";
                  smooth-scrolling-threshold = if isLaptop then 10 else 5;
                  on-scroll-up = "${pkgs.playerctl}/bin/playerctl next";
                  on-scroll-down = "${pkgs.playerctl}/bin/playerctl previous";
                };
              }
              (mkIf (cfg.type == "river") (
                {
                  modules-left = (map (i: "custom/tag#${toString i}") (range 1 9)) ++ [
                    "custom/layout"
                    "custom/window"
                  ];
                  "custom/layout" = {
                    exec = "${pkgs.runtimeShell} ${pkgs.oxbow.src}/contrib/waybar/scripts/layout.sh";
                    return-type = "json";
                    on-click = "${pkgs.oxbow}/bin/oxctl layout next";
                  };
                  "custom/window" = {
                    exec = "${pkgs.runtimeShell} ${pkgs.oxbow.src}/contrib/waybar/scripts/window.sh";
                    return-type = "json";
                    escape = true;
                    max-length = 60;
                  };
                }
                // listToAttrs (
                  map (
                    i:
                    nameValuePair "custom/tag#${toString i}" {
                      exec = "${pkgs.runtimeShell} ${pkgs.oxbow.src}/contrib/waybar/scripts/tag.sh --show-empty ${toString i}";
                      return-type = "json";
                      on-click = "${pkgs.oxbow}/bin/oxctl tag view ${toString i}";
                      on-click-right = "${pkgs.oxbow}/bin/oxctl tag toggle ${toString i}";
                    }
                  ) (range 1 9)
                )
              ))
            ])
          ];
          style = ''
            * {
              font-size: ${toString (config.gtk.font.size * 4 / 3)}px;
            }

            #custom-tag.viewed { color: #7aa2f7; }

            window#waybar {
              background: @theme_base_color;
              border-bottom: 1px solid @unfocused_borders;
              color: @theme_text_color;
            }
          '';
          # Use custom systemd
          systemd.enable = false;
        };

      systemd.user.services.waybar = {
        Unit = {
          Description = "Highly customizable Wayland bar for Sway and Wlroots based compositors.";
          Documentation = "https://github.com/Alexays/Waybar/wiki";
          BindsTo = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
          Wants = [ "tray.target" ];
          Before = [ "tray.target" ];
        };

        Service = {
          ExecStart = "${pkgs.waybar}/bin/waybar";
          Environment = "PATH=${
            lib.makeBinPath [
              pkgs.oxbow
              pkgs.jq
              pkgs.coreutils
            ]
          }";
          ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR2 $MAINPID";
          Restart = "on-failure";
          KillMode = "mixed";
          Slice = "session-graphical.slice";
        };

        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };
    })
    (mkIf cfg.screen.gamma.enable {
      services.wlsunset = {
        enable = true;
      }
      // (getAttr cfg.screen.gamma.loc locs);

    })
  ]);
}
