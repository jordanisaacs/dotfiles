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

  dwlJD = pkgs.dwlBuilder {
    config = {
      input = {
        natscroll = systemCfg ? laptop && systemCfg.laptop.enable;
      };
      cmds = {
        term = [ "${pkgs.ghostty}/bin/ghostty" ];
        menu = menuCmd;
        quit = [ "${wayExit}" ];
        audioup = audioUpCmd;
        audiodown = audioDownCmd;
        audiomut = audioMutCmd;
      };
      visual.cursorSize = config.jd.graphical.cursor.size;
    };
  };

  wayExitPackage = desktopScript "wayexit" {
    action = "exit";
    uwsm = "${pkgs.uwsm}/bin/uwsm";
  };
  wayExit = "${wayExitPackage}/bin/wayexit";

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
    backend = cfg.type;
    uwsm = "${pkgs.uwsm}/bin/uwsm";
    randr = "${pkgs.wlr-randr}/bin/wlr-randr";
    cacheHome = config.xdg.cacheHome;
  };
  sessionEntry = desktopScript "wayland-session" {
    action = "session";
    uwsm = "${pkgs.uwsm}/bin/uwsm";
    command =
      if isRiver then
        [ "${pkgs.river}/bin/river" ]
      else if isDwl then
        [
          "${dwlJD}/bin/dwl"
          "-s"
          "${compositorStartup}/bin/compositor-setup"
        ]
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
    action = "command";
    command = [ "${pkgs.oxbow}/bin/oxbow" ];
  };

  isSway = cfg.type == "sway";
  isSwayDbg = cfg.type == "sway-dbg";
  isDwl = cfg.type == "dwl";
  isRiver = cfg.type == "river";
in
{
  options.jd.graphical.wayland = {
    type = mkOption {
      type = types.enum [
        "dwl"
        "sway"
        "sway-dbg"
        "river"
      ];
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

      home.packages = [
        captureBins
        pkgs.uwsm
      ];
      programs.fuzzel = {
        enable = true;
        settings.main = {
          terminal = "${pkgs.ghostty}/bin/ghostty -e";
          launch-prefix = "${pkgs.uwsm}/bin/uwsm app -t service --";
          font = "Berkeley Mono Variable:size=14";
        };
      };

      home.file.".winitrc".source = "${sessionEntry}/bin/wayland-session";
    }
    (mkIf (isSway || isSwayDbg) {
      home.packages = [ pkgs.sway ];
      xdg.configFile."sway/config".text = swayConfig;

    })
    (mkIf isDwl {
      home.packages = [ dwlJD ];

    })
    (mkIf isRiver {
      home.packages = [
        pkgs.river
        pkgs.oxbow
      ];
      assertions = [
        {
          assertion = lib.versionAtLeast pkgs.river.version "0.4.6";
          message = "Oxbow requires River >= 0.4.6 with river-window-management-v1.";
        }
      ];
      xdg.configFile."river/init".source = "${riverInit}/bin/river-init";
      xdg.configFile."oxbow/init".source = "${oxbowInit}/bin/oxbow-init";

    })
  ]);
}
