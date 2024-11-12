{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.jd.graphical.wayland;
  systemCfg = config.machineData.systemConfig;
  bemenuCmd = pkgs.writeShellScript "bemenu-wrapper" ''
    BEMENU_SCALE=2 ${pkgs.bemenu}/bin/bemenu -i -l 8 --scrollbar autohide
  '';
  menuCmd = [
    "${pkgs.j4-dmenu-desktop}/bin/j4-dmenu-desktop"
    "--dmenu='${bemenuCmd}'"
    "--term='${pkgs.foot}/bin/foot'"
    "--no-generic"
  ];
  audioUpCmd = [ "${pkgs.scripts.soundTools}/bin/stools" "vol" "up" "5" ];
  audioDownCmd = [ "${pkgs.scripts.soundTools}/bin/stools" "vol" "down" "5" ];
  audioMutCmd = [ "${pkgs.scripts.soundTools}/bin/stools" "vol" "toggle" ];
  captureDisplays = pkgs.writeShellScriptBin "wl-capture-displays" ''
    ${pkgs.grim}/bin/grim - | ${pkgs.wl-clipboard}/bin/wl-copy
  '';
  captureDisplay = pkgs.writeShellScriptBin "wl-capture-display" ''
    ${pkgs.grim}/bin/grim -o "$(${pkgs.slurp}/bin/slurp -o -f "%o")" - | ${pkgs.wl-clipboard}/bin/wl-copy
  '';
  captureRegion = pkgs.writeShellScriptBin "wl-capture-region" ''
    ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - | ${pkgs.wl-clipboard}/bin/wl-copy
  '';
  captureBins = pkgs.symlinkJoin {
    name = "wl-capture-bins";
    paths = [ captureDisplays captureDisplay captureRegion ];
  };

  dwlJD = pkgs.dwlBuilder {
    config = {
      input = { natscroll = systemCfg ? laptop && systemCfg.laptop.enable; };
      cmds = {
        term = [ "${pkgs.foot}/bin/foot" ];
        menu = menuCmd;
        quit = [ "${wayExit}" ];
        audioup = audioUpCmd;
        audiodown = audioDownCmd;
        audiomut = audioMutCmd;
      };
      visual.cursorSize = config.jd.graphical.cursor.size;
    };
  };

  wayExit = pkgs.writeScript "wayexit" ''
    systemctl --user stop graphical-session.target
    systemctl --user stop graphical-session-pre.target

    # Wait until the units actually stop.
    while [ -n "$(systemctl --user --no-legend --state=deactivating list-units)" ];
    do
      sleep 0.2
    done

    ${optionalString (isSway || isSwayDbg) "swaymsg exit"}
    ${optionalString isRiver "riverctl exit"}
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
    systemctl import-environment --user DISPLAY WAYLAND_DISPLAY XDG_SESSION_TYPE DBUS_SESSION_BUS_ADDRESS \
      QT_QPA_PLATFORMTHEME PATH XCURSOR_SIZE XCURSOR_THEME

    ${optionalString isDwl ''
      wlr-randr --output "HDMI-A-1" --transform 90 --pos 0,0
      wlr-randr --output "DP-1" --transform normal --pos 1440,400
      systemctl --user start dwl-session.target
      exec cp /dev/stdin $XDG_CACHE_HOME/dwltags
    ''}
    ${optionalString (isSway || isSwayDbg) ''
      systemctl --user start sway-session.target
    ''}
    ${optionalString isRiver ''
      systemctl --user start river-session.target
    ''}
  '';

  isSway = cfg.type == "sway";
  isSwayDbg = cfg.type == "sway-dbg";
  isDwl = cfg.type == "dwl";
  isRiver = cfg.type == "river";
in {
  options.jd.graphical.wayland = {
    type = mkOption {
      type = types.enum [ "dwl" "sway" "sway-dbg" "river" ];
      description = ''What desktop/wm to use. Options: "dwl", "sway"'';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [{
        assertion = systemCfg.graphical.wayland.enable;
        message = "To enable wayland for user, it must be enabled for system";
      }];

      home.packages = [ captureBins ];

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
            export CLUTTER_BACKEND=wayland
            export SDL_VIDEODRIVER=wayland

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
            ${optionalString isRiver ''
              ${pkgs.river-master}/bin/river
            ''}
          '';
        };
      };
    }
    (mkIf (isSway || isSwayDbg) {
      home.packages = [ pkgs.sway ];
      xdg.configFile."sway/config".text = swayConfig;

      systemd.user.targets.sway-session = {
        Unit = {
          Description = "sway compositor session";
          Documentation = [ "man:systemd.special(7)" ];
          BindsTo = [ "wayland-session.target" ];
          After = [ "wayland-session.target" ];
        };
      };
    })
    (mkIf isDwl {
      home.packages = [ dwlJD ];
      systemd.user.targets.dwl-session = {
        Unit = {
          Description = "dwl compositor session";
          Documentation = [ "man:systemd.special(7)" ];
          BindsTo = [ "wayland-session.target" ];
          After = [ "wayland-session.target" ];
        };
      };
    })
    (mkIf isRiver {
      home.packages = [ pkgs.rivercarro-master ];
      wayland.windowManager.river = let layout = "rivercarro";
      in {
        enable = true;
        package = pkgs.river-master;
        settings = let
          num_tags = 9;
          all_tags = "$(((1 << ${toString num_tags}) - 1))";
          mod_key = "Super";
        in zipAttrs ([{
          map.normal."${mod_key}+Shift Return".spawn = "foot";
          map.normal."${mod_key} P".spawn = ''"''
            + (concatStringsSep " " menuCmd) + ''"'';

          map.normal."None Print".spawn =
            ''"${captureRegion}/bin/wl-capture-region"'';
          map.normal."${mod_key} Print".spawn =
            ''"${captureDisplay}/bin/wl-capture-display"'';
          map.normal."${mod_key}+Shift Print".spawn =
            ''"${captureDisplays}/bin/wl-capture-displays"'';

          map.normal."${mod_key}+Shift C" = "close";
          map.normal."${mod_key}+Shift Q".spawn = "${wayExit}";
          map.normal."${mod_key} J".focus-view = "next";
          map.normal."${mod_key} K".focus-view = "previous";
          map.normal."${mod_key}+Shift J".swap = "next";
          map.normal."${mod_key}+Shift K".swap = "previous";
          map.normal."${mod_key} Period".focus-output = "next";
          map.normal."${mod_key} Comma".focus-output = "previous";
          map.normal."${mod_key}+Shift Period".send-to-output = "next";
          map.normal."${mod_key}+Shift Comma".send-to-output = "previous";
          map.normal."${mod_key} Return" = "zoom";

          left-pointer.normal."${mod_key} BTN_LEFT" = "move-view";
          map-pointer.normal."${mod_key} BTN_RIGHT" = "resize-view";
          map-pointer.normal."${mod_key} BTN_MIDDLE" = "move-view";

          map.normal."${mod_key} 0".set-focused-tags = all_tags;
          map.normal."${mod_key}+Shift 0".set-view-tags = all_tags;

          map.normal."${mod_key} Space" = "toggle-float";
          map.normal."${mod_key} F" = "toggle-fullscreen";

          declare-mode = "passthrough";
          map.normal."${mod_key} F11".enter-mode = "passthrough";
          map.passthrough."${mod_key} F11".enter-mode = "normal";

          input."'*Touchpad'".tap = "enabled";
          input."'*Touchpad'".natural-scroll = "enabled";
          set-repeat = "50 300";
          xcursor-theme.${config.home.pointerCursor.name} =
            toString config.jd.graphical.cursor.size;
          focus-follows-cursor = "normal";

          default-layout = layout;
        }] ++ (map (index:
          let
            i = toString index;
            tags = "$((1 << (${i} - 1)))";
          in {
            map.normal."${mod_key} ${i}".set-focused-tags = tags;
            map.normal."${mod_key}+Shift ${i}".set-view-tags = tags;
            map.normal."${mod_key}+Control ${i}".toggle-focused-tags = tags;
            map.normal."${mod_key}+Shift+Control ${i}".toggle-view-tags = tags;
          }) (range 1 num_tags))
          ++ (optional (layout == "rivercarro" || layout == "rivertile") ({
            map.normal."${mod_key} H".send-layout-cmd.${layout} =
              "'main-ratio -0.05'";
            map.normal."${mod_key} L".send-layout-cmd.${layout} =
              "'main-ratio +0.05'";
            map.normal."${mod_key} I".send-layout-cmd.${layout} =
              "'main-count +1'";
            map.normal."${mod_key} D".send-layout-cmd.${layout} =
              "'main-count -1'";
          }) ++ (map (keys: {
            map.normal."${mod_key}${elemAt keys 0}".send-layout-cmd.${layout} =
              "'main-location top'";
            map.normal."${mod_key}${elemAt keys 1}".send-layout-cmd.${layout} =
              "'main-location left'";
            map.normal."${mod_key}${elemAt keys 2}".send-layout-cmd.${layout} =
              "'main-location bottom'";
            map.normal."${mod_key}${elemAt keys 3}".send-layout-cmd.${layout} =
              "'main-location right'";
          }) [
            [ " Up" " Left" " Down" " Right" ]
            [ "+Shift W" "+Shift A" "+Shift S" "+Shift D" ]
          ])) ++ (optional (layout == "rivercarro") {
            map.normal."${mod_key} M".send-layout-cmd.${layout} =
              "'main-location monocle'";
            map.normal."${mod_key} T".send-layout-cmd.${layout} =
              "'main-location left'";
          }));
        extraConfig = ''
          ${layout} &
          ${compositorStartup}/bin/compositor-setup
        '';
        # Do custom systemd instead
        systemd.enable = false;
      };

      systemd.user.targets.river-session = {
        Unit = {
          Description = "river compositor session";
          Documentation = [ "man:systemd.special(7)" ];
          BindsTo = [ "wayland-session.target" ];
          After = [ "wayland-session.target" ];
        };
      };
    })
  ]);
}
