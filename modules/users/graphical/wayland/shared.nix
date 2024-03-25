{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.graphical.wayland;
  systemCfg = config.machineData.systemConfig;
  isLaptop = systemCfg ? framework && systemCfg.framework.enable;
  isDwl = cfg.type == "dwl";
  isRiver = cfg.type == "river";

  dwlTags = pkgs.writeShellApplication {
    name = "dwl-waybar";
    runtimeInputs = with pkgs; [ gnugrep inotify-tools coreutils gnused gawk ];
    text = builtins.readFile ./dwl.sh;
  };

  screenNames =
    if isLaptop
    then [ "eDP-1" ]
    else [ "HDMI-A-1" "DP-1" ];

  # wlr-randr --on does not work for some reason on dwl. not using currently
  poweroffScreen = pkgs.writeShellApplication {
    name = "poweroff-screen";
    runtimeInputs = with pkgs; [ wlr-randr ];
    text = builtins.concatStringsSep "\n" (builtins.map screenNames (v: "wlr-randr --output ${v} --off"));
  };

  poweronScreen = pkgs.writeShellApplication {
    name = "poweron-screen";
    runtimeInputs = with pkgs; [ wlr-randr ];
    text = builtins.concatStringsSep "\n" (builtins.map screenNames (v: "wlr-randr --output ${v} --on"));
  };

  toggleservice = pkgs.writeShellApplication {
    name = "toggleservice";
    runtimeInputs = with pkgs; [ systemd ];
    text = ''
      if systemctl is-active --quiet --user "$1"; then
        systemctl stop --user "$1"
      else
        systemctl start --user "$1"
      fi
    '';
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
        type = types.enum [ "stretch" "fill" "fit" "center" "tile" ];
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
        type = types.enum [ "waylock" "swaylock" ];
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
        default =
          if (isDwl || isRiver) then
            pkgs.waybar-master.override { swaySupport = false; hyprlandSupport = false; }
          else
            pkgs.waybar-master;
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

    foot = {
      theme = mkOption {
        type = with types; enum [ "tokyo-night" "dracula" ];
        description = "Theme for foot";
        default = "tokyo-night";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      home.packages = with pkgs; [
        foot
        bemenu
        wl-clipboard
        wlr-randr
        wdisplays
        libappindicator-gtk3
        mako
      ];

      xdg.portal = {
        enable = true;
        extraPortals = [ pkgs.xdg-desktop-portal-wlr pkgs.xdg-desktop-portal-gtk ];
        config.dwl.default = [ "wlr" "gtk" ];
      };

      xdg.mimeApps = {
        associations.added = {
          "x-scheme-handler/terminal" = "foot.desktop";
        };

        defaultApplications = {
          "x-scheme-handler/terminal" = "foot.desktop";
        };
      };

      programs.foot = {
        enable = true;
        settings =
          let
            dracula = {
              alpha = "1.0";
              foreground = "f8f8f2";
              background = "282a36";
              regular0 = "000000"; # black
              regular1 = "ff5555"; # red
              regular2 = "50fa7b"; # green
              regular3 = "f1fa8c"; # yellow
              regular4 = "bd93f9"; # blue
              regular5 = "ff79c6"; # magenta
              regular6 = "8be9fd"; # cyan
              regular7 = "bfbfbf"; # white
              bright0 = "4d4d4d"; # bright black
              bright1 = "ff6e67"; # bright red
              bright2 = "5af78e"; # bright green
              bright3 = "f4f99d"; # bright yellow
              bright4 = "caa9fa"; # bright blue
              bright5 = "ff92d0"; # bright magenta
              bright6 = "9aedfe"; # bright cyan
              bright7 = "e6e6e6"; # bright white
            };

            tokyoNight = {
              background = "1a1b26";
              foreground = "c0caf5";
              regular0 = "15161E";
              regular1 = "f7768e";
              regular2 = "9ece6a";
              regular3 = "e0af68";
              regular4 = "7aa2f7";
              regular5 = "bb9af7";
              regular6 = "7dcfff";
              regular7 = "a9b1d6";
              bright0 = "414868";
              bright1 = "f7768e";
              bright2 = "9ece6a";
              bright3 = "e0af68";
              bright4 = "7aa2f7";
              bright5 = "bb9af7";
              bright6 = "7dcfff";
              bright7 = "c0caf5";
            };
          in
          {
            main = {
              pad = "2x2 center";
              font = "Berkeley Mono Variable:size=20,Noto Color Emoji:style=Regular:size=20";
            };
            cursor = {
              color = "282a36 f8f8f2";
            };
            colors =
              if (cfg.foot.theme == "tokyo-night")
              then tokyoNight
              else dracula;
          };
      };

      systemd.user.targets.wayland-session = {
        Unit = {
          Description = "wayland graphical session";
          BindsTo = [ "graphical-session.target" ];
          Wants = [ "graphical-session-pre.target" ];
          After = [ "graphical-session-pre.target" ];
        };
      };
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
              if cfg.screenlock.type == "waylock"
              then "${pkgs.waylock}/bin/waylock -fork-on-lock"
              else "${pkgs.swaylock}/bin/swaylock -f";
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

            events = [
              {
                event = "before-sleep";
                command = lockCommand;
              }
            ];
            systemdTarget = "wayland-session.target";
            extraArgs = [ "idlehint 600" ];
          };

        home.packages = with pkgs;
          (optional (cfg.screenlock.type == "waylock") waylock)
          ++ (optional (cfg.screenlock.type == "swaylock") swaylock);
      }
    ))
    (mkIf cfg.background.enable {
      home.packages = [ pkgs.swaybg ];

      systemd.user.services.swaybg = mkIf cfg.background.enable {
        Unit = {
          Description = "swaybg background service";
          Documentation = [ "man:swabyg(1)" ];
          Requires = [ "wayland-session.target" ];
          After = [ "wayland-session.target" ];
          Before = mkIf cfg.statusbar.enable [ "waybar.service" ];
        };

        Service = {
          ExecStart = "${cfg.background.pkg}/bin/swaybg --image ${cfg.background.image} --mode ${cfg.background.mode}";
        };

        Install = {
          WantedBy = [ "wayland-session.target" ];
        };
      };
    })
    (mkIf cfg.statusbar.enable {
      programs.waybar =
        let
          primaryDisplay =
            if isLaptop
            then "eDP-1"
            else "DP-1";

          dwlModule = dispName: {
            exec = "${dwlTags}/bin/dwl-waybar '${dispName}'";
            format = "{}";
            max-length = 75;
            return-type = "json";
          };
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
                modules-right = [ "cpu" "memory" "temperature" "battery" "backlight" "custom/media" "pulseaudio" "network" "idle_inhibitor" "tray" ];

                gtk-layer-shell = true;
                modules = {
                  clock = {
                    format = "{:%I:%M %p}";
                    tooltip = true;
                    tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
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
                  battery = {
                    bat = "BAT1";
                    states = {
                      good = 80;
                      warning = 30;
                      critical = 15;
                    };
                    format = "{capacity}% {icon}";
                    format-charging = "{capacity}% 󱎗";
                    format-plugged = "{capacity}% ";
                    format-alt = "{time} {icon}";
                    format-icons = [ "" "" "" "" "" ];
                    tooltip = true;
                    tooltip-format = "{timeTo}";
                  };
                  backlight =
                    {
                      device = "acpi_video1";
                      format = "{percent}% {icon}";
                      format-icons = [ "" "" ];
                      on-scroll-up = "${pkgs.light}/bin/light -A 1";
                      on-scroll-down = "${pkgs.light}/bin/light -U 1";
                      on-click = "${toggleservice}/bin/toggleservice autobrightness.service";
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
                      "default" = [ "" "" "" ];
                    };
                    on-scroll-up = "${pkgs.scripts.soundTools}/bin/stools vol up 1";
                    on-scroll-down = "${pkgs.scripts.soundTools}/bin/stools vol down 1";
                    on-click-right = "${pkgs.scripts.soundTools}/bin/stools vol toggle";
                    on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
                    tooltip = true;
                  };
                  network = {
                    interval = 60;
                    interface = "wl*";
                    format-icons = {
                      wifi = [ "󰤟" "󰤢" "󰤨" ];
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
                    exec = "${pkgs.playerctl}/bin/playerctl -a metadata --format '{\"text\": \"{{playerName}}: {{artist}} - {{markup_escape(title)}}\", \"tooltip\": \"{{playerName}} : {{markup_escape(title)}}\", \"alt\": \"{{status}}\", \"class\": \"{{status}}\"}' -F";
                    on-click = "${pkgs.playerctl}/bin/playerctl play-pause";
                    smooth-scrolling-threshold =
                      if isLaptop
                      then 10
                      else 5;
                    on-scroll-up = "${pkgs.playerctl}/bin/playerctl next";
                    on-scroll-down = "${pkgs.playerctl}/bin/playerctl previous";
                  };
                };
              }
              (mkIf (cfg.type == "river")
                {
                  modules-left = [ "river/tags" "river/mode" "river/layout" "river/window" ];
                }
              )
            ])
            (mkIf (!isLaptop)
              (mkMerge [
                (mkIf isDwl {
                  output = "HDMI-A-1";
                  modules-left = [ "custom/dwl" ];
                  modules = {
                    "custom/dwl" = dwlModule "HDMI-A-1";
                  };
                })
              ]))
          ];
          style = ''
            * {
              font-size: 24px;
            }

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
          BindsTo = [ "wayland-session.target" ];
          After = [ "wayland-session.target" ];
          Wants = [ "tray.target" ];
          Before = [ "tray.target" ];
        };

        Service = {
          ExecStart = "${pkgs.waybar}/bin/waybar";
          ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR2 $MAINPID";
          Restart = "on-failure";
          KillMode = "mixed";
        };

        Install = {
          WantedBy = [ "wayland-session.target" ];
        };
      };
    })
    (mkIf cfg.screen.gamma.enable {
      services.wlsunset =
        {
          enable = true;
        }
        // (getAttr cfg.screen.gamma.loc locs);

      systemd.user.services.wlsunset.Unit.PartOf = lib.mkForce [ "wayland-session.target" ];
    })
  ]);
}
