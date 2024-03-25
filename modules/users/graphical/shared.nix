{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.graphical;
in
{
  options.jd.graphical = {
    theme = mkOption {
      type = with types; enum [ "arc-dark" "materia-dark" ];
      description = "Enable wayland";
      default = "arc-dark";
    };

    cursor = {
      size = mkOption {
        type = types.int;
        default = 32;
        description = "Cursor size";
      };
    };
  };

  config =
    mkIf (cfg.xorg.enable || cfg.wayland.enable)
      {
        home = {
          sessionVariables = {
            QT_QPA_PLATFORMTHEME = "qt5ct";
          };

          packages = with pkgs; [
            # qt
            libsForQt5.qtstyleplugin-kvantum
            qt5ct

            xdg-utils

            # Fonts
            (nerdfonts.override { fonts = [ "JetBrainsMono" "Monaspace"]; })
            emacs-all-the-icons-fonts
            noto-fonts-emoji
            roboto
            bm-font
            noto-fonts-cjk # Chinese
            dejavu_fonts
            liberation_ttf
            corefonts # microsoft
            carlito

            fontpreview
            emote
            #openmoji-color

            jdpkgs.la-capitaine-icon-theme

            gnome.seahorse
          ];
        };

        home.pointerCursor = {
          package = pkgs.volantes-cursors;
          name = "volantes_cursors";
          size = cfg.cursor.size;
          # Pass through config to gtk
          # https://github.com/nix-community/home-manager/blob/693d76eeb84124cc3110793ff127aeab3832f95c/modules/config/home-cursor.nix#L152
          gtk.enable = true;
        };

        fonts.fontconfig.enable = true;

        gtk = {
          enable = true;
          theme = mkMerge [
            (mkIf (cfg.theme == "arc-dark") {
              package = with pkgs; arc-theme;
              name = "Arc-Dark";
            })
            (mkIf (cfg.theme == "materia-dark") {
              package = with pkgs; materia-theme;
              name = "Materia-dark";
            })
          ];

          iconTheme = {
            package = null;
            name = "la-capitaine-icon-theme";
          };

          font = {
            # already installed in profile
            package = null;
            name = "Berkeley Mono Variable";
            size = 10;
          };
        };

        # https://github.com/nix-community/home-manager/issues/2064
        systemd.user.targets.tray = lib.mkForce {
          Unit = {
            Description = "Home manager system tray";
            Requires = [ "graphical-session-pre.target" ];
            After = [ "xdg-desktop-portal-gtk.service" ];
          };
        };

        xdg = {
          systemDirs.data = [
            "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}"
            "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
          ];

          configFile = {
            "fontconfig/conf.d/04-font-priority.conf" =
              let
                fcBool = x: "<bool>" + (boolToString x) + "</bool>";
                renderConf = ''
                  <?xml version='1.0'?>
                  <!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
                  <fontconfig>
                    <!-- Default rendering settings -->
                    <alias>
                      <family>Berkeley Mono Variable</family>
                      <prefer>
                        <family>Berkeley Mono Variable</family>
                        <family>JetbrainsMonoNL NFM</family>
                      </prefer>
                    </alias>
                  </fontconfig>
                '';
              in
              {
                text = renderConf;
              };

            "qt5ct/qt5ct.conf" = {
              text = ''
                [Appearance]
                icon_theme=la-capitaine-icon-theme
                style=kvantum-dark
              '';
            };

            "Kvantum/kvantum.kvconfig" = mkMerge [
              (mkIf (cfg.theme == "arc-dark") {
                text = "theme=KvArcDark";
              })
              (mkIf (cfg.theme == "materia-dark") {
                text = "theme=MateriaDark";
              })
            ];

            "Kvantum/ArcDark" = {
              source = "${pkgs.arc-kde-theme}/share/Kvantum/ArcDark";
            };

            "Kvantum/MateriaDark" = {
              source = "${pkgs.materia-kde-theme}/share/Kvantum/MateriaDark";
            };

            "wallpapers" = {
              source = ./wallpapers;
            };

            "kdeglobals" = {
              # TODO: this is a wayland only terminal
              text = ''
                [General]
                TerminalApplication=${pkgs.foot}/bin/foot

                [KDE]
                ShowDeleteCommand=false

                [PreviewSettings]
                MaximumRemoteSize=0
              '';
            };
          };
        };

        # dconf settings set by gtk settings: https://github.com/nix-community/home-manager/blob/693d76eeb84124cc3110793ff127aeab3832f95c/modules/misc/gtk.nix#L227
        dconf.settings = {
          "org/gnome/desktop/interface" = {
            # https://askubuntu.com/questions/1404764/how-to-use-hdystylemanagercolor-scheme
            color-scheme = "prefer-dark";
            text-scaling-factor = 1.25;
            cursor-size = cfg.cursor.size;
          };
        };

        systemd.user.services.gnome-keyring = mkIf config.machineData.systemConfig.gnome.keyring.enable {
          Unit = {
            Description = "GNOME Keyring";
            PartOf = [ "graphical-session-pre.target" ];
          };

          Service = {
            ExecStart = "/run/wrappers/bin/gnome-keyring-daemon --start --foreground";
            Restart = "on-abort";
          };

          Install = { WantedBy = [ "graphical-session-pre.target" ]; };
        };
      };
}
