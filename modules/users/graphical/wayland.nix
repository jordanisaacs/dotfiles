{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
# Work in progress.
  let
    cfg = config.jd.graphical.wayland;
    systemCfg = config.machineData.systemConfig;
    dwlJD = pkgs.dwlBuilder {
      config.cmds = {
        term = ["${pkgs.foot}/bin/foot"];
        menu = ["${pkgs.bemenu}/bin/bemenu-run"];
        audioup = ["${pkgs.scripts.soundTools}/bin/stools" "vol" "up" "5"];
        audiodown = ["${pkgs.scripts.soundTools}/bin/stools" "vol" "down" "5"];
        audiomut = ["${pkgs.scripts.soundTools}/bin/stools" "vol" "toggle"];
      };
    };

    dwlStartup = pkgs.writeShellScriptBin "dwl-setup" ''
      if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
        eval $(dbus-launch --exit-with-session --sh-syntax)
      fi

      ## https://bbs.archlinux.org/viewtopic.php?id=224652
      ## Requires --systemd becuase of gnome-keyring error. Unsure how differs from systemctl --user import-environment
      if command -v dbus-update-activation-environment >/dev/null 2>&1; then
        dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP
      fi

      systemctl --user import-environment PATH XDG_RUNTIME_DIR WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
      systemctl --user start dwl-session.target
    '';

    swayStartup = pkgs.writeShellScriptBin "sway-setup" ''
      if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
        eval $(dbus-launch --exit-with-session --sh-syntax)
      fi

      ## https://bbs.archlinux.org/viewtopic.php?id=224652
      ## Requires --systemd becuase of gnome-keyring error. Unsure how differs from systemctl --user import-environment
      if command -v dbus-update-activation-environment >/dev/null 2>&1; then
        dbus-update-activation-environment --systemd --all
      fi

      ## systemctl --user import-environment PATH
      systemctl --user restart xdg-desktop-portal-gtk.service
      systemctl --user start sway-session.target
    '';

    swayConfig = ''
      exec ${swayStartup}/bin/sway-setup

      # Alt key
      set $mod Mod1

      set $left h
      set $down j
      set $up k
      set $right l

      set $term ${pkgs.foot}/bin/foot
      set $menu ${pkgs.j4-dmenu-desktop}/bin/j4-dmenu-desktop --dmenu="BEMENU_SCALE=2 ${pkgs.bemenu}/bin/bemenu -i -l 8 --scrollbar autohide" --term="$term" --no-generic | xargs swaymsg exec --

      bindsym $mod+Shift+Return exec $term
      bindsym $mod+Shift+c kill
      bindsym $mod+p exec '$menu'
      bindsym $mod+Shift+q exec swaynag -t warning -m 'Do you really want to exit?' -B 'Yes' 'swaymsg exit'

      bindsym $mod+g+$left focus left
      bindsym $mod+g+$down focus down
      bindsym $mod+g+$up focus up
      bindsym $mod+g+$right focus right

      bindsym $mod+v splitv
      bindsym $mod+b splith

      bindsym $mod+a focus parent

      bindsym $mod+Shift+$left move left
      bindsym $mod+Shift+$down move down
      bindsym $mod+Shift+$up move up
      bindsym $mod+Shift+$right move right

      bindsym $mod+r+$left resize shrink width 5px
      bindsym $mod+r+$down resize grow height 5px
      bindsym $mod+r+$up resize shrink height 5px
      bindsym $mod+r+$right resize grow width 5px

      bindsym $mod+Shift+space fullscreen toggle
      bindsym $mod+m layout stacking
      bindsym $mod+t fullscreen disable, floating disable, layout default

      bindsym --locked XF86AudioRaiseVolume exec \
        ${pkgs.scripts.soundTools}/bin/stools vol up 5
      bindsym --locked XF86AudioLowerVolume exec \
        ${pkgs.scripts.soundTools}/bin/stools vol down 5
      bindsym --locked XF86AudioMute exec \
        ${pkgs.scripts.soundTools}/bin/stools vol toggle

      smart_borders on
      default_border pixel 2
      output eDP-1 scale 1

      input "type:touchpad" {
        dwt enabled
        tap enabled
        natural_scroll enabled
        drag enabled
      }
    '';
  in {
    options.jd.graphical.wayland = {
      enable = mkOption {
        type = types.bool;
        description = "Enable wayland";
      };

      type = mkOption {
        type = types.enum ["dwl" "sway"];
        description = ''What desktop/wm to use. Options: "dwl", "sway"'';
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

      screenlock = {
        enable = mkOption {
          type = types.bool;
          description = " Enable screen locking, must enable it on system as well for pamd (swaylock)";
        };

        #timeout = {
        #  script = mkOption {
        #    description = "Script to run on timeout. Default null";
        #    type = with types; nullOr package;
        #    default = null;
        #  };

        #  time = mkOption {
        #    description = "Time in seconds until run timeout script. Default 180.";
        #    type = types.int;
        #    default = 180;
        #  };
        #};

        #lock = {
        #  command = mkOption {
        #    description = "Lock command. Default xsecurelock";
        #    type = types.str;
        #    default = "${pkgs.xsecurelock}/bin/xsecurelock";
        #  };

        #  time = mkOption {
        #    description = "Time in seconds after timeout until lock. Default 180.";
        #    type = types.int;
        #    default = 180;
        #  };
        #};
      };
    };

    config = (mkIf cfg.enable) {
      assertions = [
        {
          assertion = systemCfg.graphical.wayland.enable;
          message = "To enable wayland for user, it must be enabled for system";
        }
      ];

      home.packages = with pkgs; [
        (
          if (cfg.type == "dwl")
          then dwlJD
          else sway
        )
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
        (assert systemCfg.graphical.wayland.swaylock-pam; (
          if cfg.screenlock.enable
          then swaylock
          else null
        ))
      ];

      home.file = {
        ".winitrc" = {
          executable = true;
          text = ''
            # .winitrc autogenerated. Do not edit
            . "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"

            # firefox enable wayland
            export MOZ_ENABLE_WAYLAND=1
            export MOZ_ENABLE_XINPUT2=1
            export XDG_CURRENT_DESKTOP=sway
            export TERMINAL=foot

            ${
              if (cfg.type == "dwl")
              then ''
                ${dwlJD}/bin/dwl -s "${waylandStartup}/bin/waylandStartup"
              ''
              else ''
                ${pkgs.sway}/bin/sway
              ''
            }
            wait $!
            systemctl --user stop graphical-session.target
            systemctl --user stop graphical-session-pre.target

            # Wait until the units actually stop.
            while [ -n "$(systemctl --user --no-legend --state=deactivating list-units)" ];
            do
              sleep 0.5
            done
          '';
        };
      };

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
        "sway/config" = {
          text = swayConfig;
        };
      };

      systemd.user.targets = {
        dwl-session = mkIf (cfg.type == "dwl") {
          Unit = {
            Description = "dwl compositor session";
            Documentation = ["man:systemd.special(7)"];
            BindsTo = ["wayland-session.target"];
            After = ["wayland-session.target"];
          };
        };

        sway-session = mkIf (cfg.type == "sway") {
          Unit = {
            Description = "sway compositor session";
            Documentation = ["man:systemd.special(7)"];
            BindsTo = ["wayland-session.target"];
            After = ["wayland-session.target"];
          };
        };

        wayland-session = {
          Unit = {
            Description = "sway compositor session";
            BindsTo = ["graphical-session.target"];
            After = ["graphical-session.target"];
          };
        };
      };

      systemd.user.services.swaybg = mkIf cfg.background.enable {
        Unit = {
          Description = "swaybg background service";
          Documentation = ["man:swabyg(1)"];
          BindsTo = ["wayland-session.target"];
          After = ["wayland-session.target"];
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
        Unit.After = lib.mkForce ["wayland-session.target"];
        Install.WantedBy = lib.mkForce ["wayland-session.target"];
      };
    };
  }
