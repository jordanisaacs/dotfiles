{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.graphical.wayland;
  systemCfg = config.machineData.systemConfig;
  dwlJD = pkgs.dwlBuilder {
    config = {
      input = {
        natscroll = (systemCfg ? laptop && systemCfg.laptop.enable);
      };
      cmds = {
        term = ["${pkgs.foot}/bin/foot"];
        menu = [
          "${pkgs.j4-dmenu-desktop}/bin/j4-dmenu-desktop"
          "--dmenu='${bemenuCmd}'"
          "--term='${pkgs.foot}/bin/foot'"
          "--no-generic"
        ];
        quit = ["${wayExit}"];
        audioup = ["${pkgs.scripts.soundTools}/bin/stools" "vol" "up" "5"];
        audiodown = ["${pkgs.scripts.soundTools}/bin/stools" "vol" "down" "5"];
        audiomut = ["${pkgs.scripts.soundTools}/bin/stools" "vol" "toggle"];
      };
    };
  };

  wayExit = pkgs.writeScript "wayexit" ''
    systemctl --user stop graphical-session.target
    systemctl --user stop graphical-session-pre.target

    # Wait until the units actually stop.
    while [ -n "$(systemctl --user --no-legend --state=deactivating list-units)" ];
    do
      sleep 0.5
    done

    ${optionalString (isSway || isSwayDbg) "swaymsg exit"}
  '';

  bemenuCmd = pkgs.writeShellScript "bemenu-wrapper" ''
    BEMENU_SCALE=2 ${pkgs.bemenu}/bin/bemenu -i -l 8 --scrollbar autohide
  '';

  swayConfig = ''
    exec_always ${compositorStartup}/bin/compositor-setup

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
    bindsym $mod+Shift+q exec swaynag -t warning -m 'Do you really want to exit?' -B 'Yes' ${wayExit}

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
      drag enablenot exclusive or to boolean expressiond
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
    # Need QT theme for syncthing tray
    dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP \
      XDG_SESSION_TYPE QT_QPA_PLATFORM

    # Need QT for syncthing tray
    # systemctl --user import-environment PATH XDG_RUNTIME_DIR WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
    # systemctl --user restart xdg-desktop-portal.service
    ${optionalString isDwl ''
      wlr-randr --output "HDMI-A-1" --transform 90 --pos 0,0
      wlr-randr --output "DP-1" --transform normal --pos 1440,400
      systemctl --user start dwl-session.target
      exec cp /dev/stdin /tmp/dwltags
    ''}
    ${optionalString (isSway || isSwayDbg) "systemctl --user start sway-session.target"}
  '';

  isSway = cfg.type == "sway";
  isSwayDbg = cfg.type == "sway-dbg";
  isDwl = cfg.type == "dwl";
in {
  options.jd.graphical.wayland = {
    type = mkOption {
      type = types.enum ["dwl" "sway" "sway-dbg"];
      description = ''What desktop/wm to use. Options: "dwl", "sway"'';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = systemCfg.graphical.wayland.enable;
          message = "To enable wayland for user, it must be enabled for system";
        }
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
            export BEMENU_SCALE=2

            ${optionalString isDwl ''
              ${dwlJD}/bin/dwl -s "${compositorStartup}/bin/compositor-setup"
            ''}
            ${optionalString isSway ''
              ${pkgs.sway}/bin/sway
            ''}
            ${optionalString isSwayDbg ''
              mkdir -p ${config.xdg.stateHome}/sway
              ${pkgs.sway}/bin/sway --debug > ${config.xdg.stateHome}/sway/sway.log 2>&1
            ''}
          '';
        };
      };
    }
    (mkIf (isSway || isSwayDbg) {
      home.packages = [pkgs.sway];
      xdg.configFile."sway/config".text = swayConfig;

      systemd.user.targets.sway-session = {
        Unit = {
          Description = "sway compositor session";
          Documentation = ["man:systemd.special(7)"];
          BindsTo = ["wayland-session.target"];
          After = ["wayland-session.target"];
        };
      };
    })
    (mkIf isDwl {
      home.packages = [dwlJD];
      systemd.user.targets.dwl-session = {
        Unit = {
          Description = "dwl compositor session";
          Documentation = ["man:systemd.special(7)"];
          BindsTo = ["wayland-session.target"];
          After = ["wayland-session.target"];
        };
      };
    })
  ]);
}
