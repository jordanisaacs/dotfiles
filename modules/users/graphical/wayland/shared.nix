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
      preferredFontSize = mkOption {
        type = types.numbers.positive;
        default = 20;
        description = ''
          Preferred terminal font size in points at output scale 1. The
          configured size is divided by the internal display scale so raising
          the desktop scale preserves the terminal's physical text size.
        '';
      };
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
          font-family =
            config.fonts.fontconfig.defaultFonts.monospace ++ config.fonts.fontconfig.defaultFonts.emoji;
          # Font points become logical pixels at 96 DPI, then output scale
          # converts to physical pixels. Keep the preferred terminal size.
          font-size =
            cfg.terminal.preferredFontSize / (if cfg.display.enable then cfg.display.internalScale else 1.0);
          theme = if cfg.terminal.theme == "tokyo-night" then "TokyoNight" else "Dracula";
          window-padding-x = 2;
          window-padding-y = 2;
          window-decoration = false;
        };
      };

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
    (mkIf cfg.screen.gamma.enable {
      services.wlsunset = {
        enable = true;
      }
      // (getAttr cfg.screen.gamma.loc locs);

    })
  ]);
}
