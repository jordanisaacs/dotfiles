{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.graphical;
  systemCfg = config.machineData.systemConfig;
in
{
  config = mkIf (cfg.xorg.enable == true || cfg.wayland.enable == true)
    {
      home.packages = with pkgs; mkIf (systemCfg.connectivity.sound.enable) [
        calibre
        pavucontrol
        pasystray
        myPkgs.volantes-cursors
        authy
        spotify

        # qt
        libsForQt5.qtstyleplugin-kvantum
        qt5ct
      ];

      home.file = {
        "${config.xdg.configHome}/wallpapers" = {
          source = ./wallpapers;
        };

        ".icons/default/index.theme" = {
          text = ''
            [icon theme]
            Inherits=volantes_cursors
          '';
        };

        ".icons/volantes_cursors" = {
          source = "${pkgs.myPkgs.volantes-cursors}/usr/share/icons/volantes-cursors";
        };

        ".icons/la_capitaine_icon_theme" = {
          source = "${pkgs.myPkgs.la-capitaine-icon-theme}/share/icons/la-capitaine-icon-theme";
        };

        ".icons/breeze" = {
          source = "${pkgs.breeze-icons}/share/icons/breeze";
        };

        ".icons/elementary" = {
          source = "${pkgs.pantheon.elementary-icon-theme}/share/icons/elementary";
        };

        ".icons/gnome" = {
          source = "${pkgs.gnome-icon-theme}/share/icons/gnome";
        };

        ".icons/hicolor" = {
          source = "${pkgs.hicolor-icon-theme}/share/icons/hicolor";
        };

        #".icons/elementary" = {
        #  source = "${pkgs.pantheon.la-capitaine-icon-theme}/share/";
        #};

        #".icons/gnome" = {
        #  source = "${pkgs.myPkgs.la-capitaine-icon-theme}/share/";
        #};

        #".icons/deepin" = {
        #  source = "${pkgs.myPkgs.la-capitaine-icon-theme}/share/";
        #};
      };

      xdg.configFile = {
        "qt5ct/qt5ct.conf" = {
          text = ''
            [Appearance]
            icon_theme=la_capitaine_icon_theme
            style=kvantum-dark
          '';
        };

        "Kvantum/kvantum.kvconfig" = {
          text = ''
            theme=ArcDark
          '';
        };

        "Kvantum/ArcDark" = {
          source = "${pkgs.arc-kde-theme}/share/Kvantum/ArcDark";
        };
      };

      gtk = {
        enable = true;
        theme = {
          package = with pkgs; arc-theme;
          name = "Arc-Dark";
        };
        iconTheme = {
          name = "la_capitaine_icon_theme";
        };
        gtk3.extraConfig = {
          gtk-cursor-theme-name = "volantes_cursors";
          gtk-application-prefer-dark-theme = true;
        };
      };

      home.sessionVariables = {
        QT_QPA_PLATFORMTHEME = "qt5ct";
      };

      xdg.systemDirs.data = [
        "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}"
        "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
      ];

      dconf.settings = {
        "org/gnome/desktop/interface" = {
          cursor-theme = "volantes_cursors";
          icon-theme = "la_capitaine_icon_theme";
          text-scaling-factor = 1.25;
        };
      };

      services = {
        gnome-keyring.enable = true;
      };
    };
}






