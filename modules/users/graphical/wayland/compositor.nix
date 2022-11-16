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

    swayConfig = ''
      exec ${compositorStartup}/bin/compositor-setup

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

      output "Dell Inc. DELL U2713H C6F0K32405ML" {
        transform 270
      }

      output "Acer Technologies XV320QU LV 1130182484201" {
        adaptive_sync on
        mode 2560x1440@119.998Hz
      }
    '';

    compositorStartup = pkgs.writeShellScriptBin "compositor-setup" ''
      if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
        eval $(dbus-launch --exit-with-session --sh-syntax)
      fi

      ## https://bbs.archlinux.org/viewtopic.php?id=224652
      ## Requires --systemd becuase of gnome-keyring error. Unsure how differs from systemctl --user import-environment
      if command -v dbus-update-activation-environment >/dev/null 2>&1; then
        dbus-update-activation-environment --systemd --all
      fi

      # systemctl --user import-environment PATH XDG_RUNTIME_DIR WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
      systemctl --user restart xdg-desktop-portal.service
      systemctl --user start ${
        if cfg.type == "sway"
        then "sway"
        else "dwl"
      }-session.target
    '';
  in {
    options.jd.graphical.wayland = {
      enable = mkOption {
        type = types.bool;
        description = "Enable wayland";
      };

      type = mkOption {
        type = types.enum ["dwl" "sway" "sway-dbg"];
        description = ''What desktop/wm to use. Options: "dwl", "sway"'';
      };

      screenlock = {
        # TODO: package waylock and switch from swaylock
        enable = mkOption {
          type = types.bool;
          description = "Enable screen locking, must enable it on system as well for pamd (swaylock)";
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

    config =
      mkIf cfg.enable
      {
        assertions = [
          {
            assertion = systemCfg.graphical.wayland.enable;
            message = "To enable wayland for user, it must be enabled for system";
          }
        ];

        home.packages =
          if (cfg.type == "dwl")
          then [dwlJD]
          else [pkgs.sway];

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
                  ${dwlJD}/bin/dwl -s "${compositorStartup}}/bin/compositor-setup"
                ''
                else
                  (
                    if (cfg.type == "sway")
                    then "${pkgs.sway}/bin/sway"
                    else ''
                      mkdir -p ${config.xdg.stateHome}/sway
                      ${pkgs.sway}/bin/sway --debug > ${config.xdg.stateHome}/sway/sway.log 2>&1
                    ''
                  )
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
          "sway/config" = mkIf (cfg.type == "sway") {
            text = swayConfig;
          };
        };

        systemd.user.targets = mkMerge [
          (
            mkIf (cfg.type == "dwl")
            {
              dwl-session = {
                Unit = {
                  Description = "dwl compositor session";
                  Documentation = ["man:systemd.special(7)"];
                  BindsTo = ["wayland-session.target"];
                  After = ["wayland-session.target"];
                };
              };
            }
          )
          (
            mkIf (cfg.type == "sway")
            {
              sway-session = {
                Unit = {
                  Description = "sway compositor session";
                  Documentation = ["man:systemd.special(7)"];
                  BindsTo = ["wayland-session.target"];
                  After = ["wayland-session.target"];
                };
              };
            }
          )
          {
            wayland-session = {
              Unit = {
                Description = "sway compositor session";
                BindsTo = ["graphical-session.target"];
                After = ["graphical-session.target"];
              };
            };
          }
        ];
      };
  }
