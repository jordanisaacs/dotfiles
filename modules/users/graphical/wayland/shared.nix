{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.graphical.wayland;
  systemCfg = config.machineData.systemConfig;
in {
  options.jd.graphical.wayland = {
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
        type = types.enum ["stretch" "fill" "fit" "center" "tile"];
        description = "Scaling mode for background";
      };
    };

    statusbar = {
      enable = mkOption {
        type = types.bool;
        description = "Enable status bar [waybar]";
      };

      pkg = mkOption {
        type = types.package;
        description = "Waybar package";
      };
    };

    foot = {
      theme = mkOption {
        type = with types; enum ["tokyo-night" "dracula"];
        description = "Theme for foot";
        default = "tokyo-night";
      };
    };
  };

  config =
    mkIf cfg.enable
    {
      home.packages = with pkgs; [
        foot
        bemenu
        wl-clipboard
        libappindicator-gtk3
        mako
        (
          if cfg.background.enable
          then swaybg
          else null
        )
        (assert systemCfg.graphical.wayland.swaylockPam; (
          if cfg.screenlock.enable
          then swaylock
          else null
        ))
      ];

      xdg.configFile = {
        "foot/foot.ini" = let
          dracula = ''
            alpha=1.0
            foreground=f8f8f2
            background=282a36
            regular0=000000  # black
            regular1=ff5555  # red
            regular2=50fa7b  # green
            regular3=f1fa8c  # yellow
            regular4=bd93f9  # blue
            regular5=ff79c6  # magenta
            regular6=8be9fd  # cyan
            regular7=bfbfbf  # white
            bright0=4d4d4d   # bright black
            bright1=ff6e67   # bright red
            bright2=5af78e   # bright green
            bright3=f4f99d   # bright yellow
            bright4=caa9fa   # bright blue
            bright5=ff92d0   # bright magenta
            bright6=9aedfe   # bright cyan
            bright7=e6e6e6   # bright white
          '';

          tokyoNight = ''
            background=1a1b26
            foreground=c0caf5
            regular0=15161E
            regular1=f7768e
            regular2=9ece6a
            regular3=e0af68
            regular4=7aa2f7
            regular5=bb9af7
            regular6=7dcfff
            regular7=a9b1d6
            bright0=414868
            bright1=f7768e
            bright2=9ece6a
            bright3=e0af68
            bright4=7aa2f7
            bright5=bb9af7
            bright6=7dcfff
            bright7=c0caf5
          '';
        in {
          text = ''
            pad=2x2 center
            font=JetBrainsMono Nerd Font Mono,Noto Color Emoji:style=Regular

            [cursor]
            color=282a36 f8f8f2

            [colors]
            ${
              if cfg.foot.theme == "tokyo-night"
              then tokyoNight
              else dracula
            }
          '';
        };
      };
      systemd.user.services.swaybg = mkIf cfg.background.enable {
        Unit = {
          Description = "swaybg background service";
          Documentation = ["man:swabyg(1)"];
          BindsTo = ["wayland-session.target"];
          After = ["wayland-session.target"];
          Before = mkIf (cfg.statusbar.enable) ["waybar.service"];
        };

        Service = {
          ExecStart = "${cfg.background.pkg}/bin/swaybg --image ${cfg.background.image} --mode ${cfg.background.mode}";
        };

        Install = {
          WantedBy = ["wayland-session.target"];
        };
      };

      programs.waybar = mkIf cfg.statusbar.enable {
        enable = true;
        package = cfg.statusbar.pkg;
        settings = [
          {
            layer = "bottom";

            modules-left = [];
            modules-center = ["clock"];
            modules-right = ["cpu" "memory" "temperature" "battery" "backlight" "pulseaudio" "network" "tray"];

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
              temperature = {};
              battery = {
                bat = "BAT1";
                states = {
                  good = 80;
                  warning = 30;
                  critical = 15;
                };
                format = "{capacity}% {icon}";
                format-charging = "{capacity}% ";
                format-plugged = "{capacity}% ";
                format-alt = "{time} {icon}";
                format-icons = ["" "" "" "" ""];
                tooltip = true;
                tooltip-format = "{timeTo}";
              };
              backlight = {
                device = "acpi_video1";
                format = "{percent}% {icon}";
                format-icons = ["" ""];
                on-scroll-up = "${pkgs.light}/bin/light -A 2";
                on-scroll-down = "${pkgs.light}/bin/light -U 1";
              };
              pulseaudio = {
                format = "{volume}% {icon} {format_source}";
                format-bluetooth = "{volume}% {icon} {format_source}";
                format-bluetooth-muted = "{volume}%  {format_source}";
                format-muted = "{volume}%  {format_source}";
                format-source = "{volume}% ";
                format-source-muted = "{volume}% ";
                format-icons = {
                  "default" = ["" "" ""];
                };
                on-scroll-up = "${pkgs.scripts.soundTools}/bin/stools vol up 1";
                on-scroll-down = "${pkgs.scripts.soundTools}/bin/stools vol down 1";
                on-click-right = "${pkgs.scripts.soundTools}/bin/stools vol toggle";
                on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
                tooltip = true;
              };
              network = {
                interval = 60;
                interface = "wlp*";
                format-wifi = "{essid} ({signalStrength}%) ";
                format-ethernet = "{ipaddr}/{cidr} ";
                tooltip-format = "{ifname} via {gwaddr} ";
                format-linked = "{ifname} (No IP) ";
                format-disconnected = "Disconnected ⚠";
                format-alt = "{ifname}: {ipaddr}/{cidr}";
                tooltip = true;
              };
              tray = {
                spacing = 10;
              };
            };
          }
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
        systemd.enable = true;
      };

      systemd.user.services.waybar = mkIf cfg.statusbar.enable {
        Unit.BindsTo = lib.mkForce ["wayland-session.target"];
        Unit.After = lib.mkForce ["wayland-session.target" "xdg-desktop-portal-gtk.service"];
        Install.WantedBy = lib.mkForce ["wayland-session.target"];
      };
    };
}
