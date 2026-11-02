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
  pythonScript = import ../../../../lib/python-script.nix { inherit pkgs; };
  desktopScript = name: settings: pythonScript name ../../../../scripts/desktop.py settings;
  menuCmd = [ "${pkgs.fuzzel}/bin/fuzzel" ];
  launcher = desktopScript "app-launcher" {
    action = "command";
    command = menuCmd;
  };
  audioUpCmd = [
    "${pkgs.jdScripts.soundTools}/bin/stools"
    "vol"
    "up"
    "5"
  ];
  audioDownCmd = [
    "${pkgs.jdScripts.soundTools}/bin/stools"
    "vol"
    "down"
    "5"
  ];
  audioMutCmd = [
    "${pkgs.jdScripts.soundTools}/bin/stools"
    "vol"
    "toggle"
  ];
  mkCapture =
    name: mode:
    desktopScript name {
      action = "capture";
      inherit mode;
      grim = "${pkgs.grim}/bin/grim";
      slurp = "${pkgs.slurp}/bin/slurp";
      wlCopy = "${pkgs.wl-clipboard}/bin/wl-copy";
    };
  captureDisplays = mkCapture "wl-capture-displays" "all";
  captureDisplay = mkCapture "wl-capture-display" "display";
  captureRegion = mkCapture "wl-capture-region" "region";
  captureBins = pkgs.symlinkJoin {
    name = "wl-capture-bins";
    paths = [
      captureDisplays
      captureDisplay
      captureRegion
    ];
  };

  wayExitPackage = desktopScript "wayexit" (
    if cfg.type == "river" then
      {
        action = "command";
        command = [
          "${pkgs.uwsm}/bin/uwsm"
          "app"
          "-t"
          "service"
          "--"
          "${cfg.logout.package}/bin/desktop-logout"
        ];
      }
    else
      {
        action = "exit";
        uwsm = "${pkgs.uwsm}/bin/uwsm";
      }
  );
  wayExit = "${wayExitPackage}/bin/wayexit";
  riverPackage = cfg.river.package;

  swayConfig = ''
    exec_always ${compositorStartup}/bin/compositor-setup

    # Alt key
    set $mod Mod1

    set $left h
    set $down j
    set $up k
    set $right l

    set $term ${pkgs.ghostty}/bin/ghostty
    set $menu ${launcher}/bin/app-launcher

    bindsym $mod+Shift+Return exec ${pkgs.uwsm}/bin/uwsm app -t service -- $term
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
      ${pkgs.jdScripts.soundTools}/bin/stools vol up 5
    bindsym --locked XF86AudioLowerVolume exec \
      ${pkgs.jdScripts.soundTools}/bin/stools vol down 5
    bindsym --locked XF86AudioMute exec \
      ${pkgs.jdScripts.soundTools}/bin/stools vol toggle

    smart_borders on
    default_border pixel 2
    output eDP-1 scale 1

    input "type:touchpad" {
      dwt enabled
      tap enabled
      natural_scroll enabled
      drag enabled
    }

    input "type:keyboard" {
      xkb_file ${cfg.keyboard.keymap}
      repeat_rate ${toString cfg.keyboard.repeatRate}
      repeat_delay ${toString cfg.keyboard.repeatDelay}
    }

    output "Dell Inc. DELL U2713H C6F0K32405ML" {
      transform 270
    }

    output "Acer Technologies XV320QU LV 1130182484201" {
      adaptive_sync on
      mode 2560x1440@119.998Hz
    }
  '';

  compositorStartup = desktopScript "compositor-setup" {
    action = "setup";
    uwsm = "${pkgs.uwsm}/bin/uwsm";
    systemctl = "${pkgs.systemd}/bin/systemctl";
    notify = "${pkgs.systemd}/bin/systemd-notify";
  };
  sessionEntry = desktopScript "wayland-session" {
    action = "session";
    uwsm = "${pkgs.uwsm}/bin/uwsm";
    command =
      if isRiver then
        [ "${riverPackage}/bin/river" ]
      else
        [ "${pkgs.sway}/bin/sway" ] ++ optional isSwayDbg "--debug";
    profileBin = "${config.home.profileDirectory}/bin";
    dataDirectories = config.xdg.systemDirs.data ++ [ "${config.home.profileDirectory}/share" ];
    runtimeDirectoryVariables = optional config.programs.tmux.enable "TMUX_TMPDIR";
    # These upstream values contain shell parameter/command substitutions.
    # The Python launcher constructs them from the actual login environment.
    environment =
      builtins.removeAttrs config.home.sessionVariables [
        "XDG_DATA_DIRS"
        "TMUX_TMPDIR"
      ]
      // {
        XDG_CURRENT_DESKTOP = cfg.type;
        XDG_SESSION_TYPE = "wayland";
        XDG_SESSION_DESKTOP = cfg.type;
        XDG_CONFIG_HOME = config.xdg.configHome;
        XDG_CACHE_HOME = config.xdg.cacheHome;
        XDG_DATA_HOME = config.xdg.dataHome;
        XDG_STATE_HOME = config.xdg.stateHome;
        TERMINAL = "ghostty";
        MOZ_ENABLE_WAYLAND = "1";
        BEMENU_SCALE = "2";
        CLUTTER_BACKEND = "wayland";
        SDL_VIDEODRIVER = "wayland";
        UWSM_WAIT_VARNAMES = "JD_DESKTOP_READY";
      };
  };
  oxbowInit = desktopScript "oxbow-init" {
    action = "oxbow";
    uwsm = "${pkgs.uwsm}/bin/uwsm";
    oxctl = "${pkgs.oxbow}/bin/oxctl";
    cursorTheme = config.home.pointerCursor.name;
    cursorSize = config.jd.graphical.cursor.size;
    keybindings = config.jd.keybindings or "emacs";
    touchpadScrollFactor = cfg.touchpad.scrollFactor;
    outerGap = cfg.river.gaps.outer;
    keyboardKeymap = cfg.keyboard.keymap;
    keyboardRepeatRate = cfg.keyboard.repeatRate;
    keyboardRepeatDelay = cfg.keyboard.repeatDelay;
    terminal = "${pkgs.ghostty}/bin/ghostty";
    launcher = "${launcher}/bin/app-launcher";
    inherit wayExit;
    setup = "${compositorStartup}/bin/compositor-setup";
    commandBindings = {
      Print = [ "${captureRegion}/bin/wl-capture-region" ];
      "Super+Print" = [ "${captureDisplay}/bin/wl-capture-display" ];
      "Super+Shift+Print" = [ "${captureDisplays}/bin/wl-capture-displays" ];
      XF86AudioRaiseVolume = audioUpCmd;
      XF86AudioLowerVolume = audioDownCmd;
      XF86AudioMute = audioMutCmd;
      XF86MonBrightnessUp = [
        "${pkgs.brightnessctl}/bin/brightnessctl"
        "set"
        "+4%"
      ];
      XF86MonBrightnessDown = [
        "${pkgs.brightnessctl}/bin/brightnessctl"
        "set"
        "4%-"
      ];
    };
  };
  riverInit = desktopScript "river-init" {
    action = "river-start";
    command = [ "${cfg.river.switchPackage}/bin/river-wm" ];
    windowManager = cfg.river.windowManager;
    uwsm = "${pkgs.uwsm}/bin/uwsm";
  };

  isSway = cfg.type == "sway";
  isSwayDbg = cfg.type == "sway-dbg";
  isRiver = cfg.type == "river";
in
{
  imports = [ ./river-wm.nix ];
  options.jd.graphical.wayland = {
    river = {
      package = mkOption {
        type = types.package;
        default = pkgs.river-reka;
        description = "River compositor package used by the managed desktop session.";
      };
      setupCommand = mkOption {
        type = types.listOf types.str;
        readOnly = true;
        internal = true;
        default = [ "${compositorStartup}/bin/compositor-setup" ];
        description = "Publish the active window manager's native readiness.";
      };
      windowManager = mkOption {
        type = types.enum [
          "oxbow"
          "reka"
        ];
        default = config.machineData.greetdDefaultWindowManager or "oxbow";
        description = "Default River window manager when starting a user session without a login-screen override.";
      };
      gaps.outer = mkOption {
        type = types.nullOr types.ints.unsigned;
        default = null;
        description = ''
          Oxbow outer gap in logical pixels, or null to retain its upstream default.
          The inner gap is unchanged. Oxbow retains at least half the inner gap
          at screen edges even when this is zero.
        '';
      };
    };
    type = mkOption {
      type = types.enum [
        "sway"
        "sway-dbg"
        "river"
      ];
      description = "Wayland compositor: River, Sway, or Sway with debug logging.";
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

      home.packages = [
        captureBins
        pkgs.uwsm
      ];
      programs.fuzzel = {
        enable = true;
        settings.main = {
          terminal = "${pkgs.ghostty}/bin/ghostty -e";
          launch-prefix = "${pkgs.uwsm}/bin/uwsm app -t service --";
          # Physical-DPI sizing is stable when other monitors are connected.
          dpi-aware = "yes";
          font = "${builtins.head config.fonts.fontconfig.defaultFonts.monospace}:size=12";
        };
      };

      home.file.".winitrc".source = "${sessionEntry}/bin/wayland-session";
    }
    (mkIf (isSway || isSwayDbg) {
      home.packages = [ pkgs.sway ];
      xdg.configFile."sway/config".text = swayConfig;

    })
    (mkIf isRiver {
      home.packages = [
        riverPackage
        pkgs.oxbow
      ];
      assertions = [
        {
          assertion = lib.versionAtLeast pkgs.river.version "0.4.6";
          message = "Oxbow requires River >= 0.4.6 with river-window-management-v1.";
        }
      ];
      xdg.configFile."river/init".source = "${riverInit}/bin/river-init";
      xdg.configFile."oxbow/init" = {
        source = "${oxbowInit}/bin/oxbow-init";
      };

    })
  ]);
}
