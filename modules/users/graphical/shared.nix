{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.graphical;
  systemCfg = config.machineData.systemConfig;
in {
  config =
    mkIf (cfg.xorg.enable == true || cfg.wayland.enable == true)
    {
      home.packages = with pkgs;
        mkIf (systemCfg.connectivity.sound.enable) [
          calibre
          pavucontrol
          pasystray
          jdpkgs.volantes-cursors
          authy
          spotify

          # qt
          libsForQt5.qtstyleplugin-kvantum
          qt5ct

          xdg-utils
        ];

      gtk = {
        enable = true;
        theme = {
          package = with pkgs; arc-theme;
          name = "Arc-Dark";
        };
        iconTheme = {
          name = "la-capitaine-icon-theme";
        };
        gtk3.extraConfig = {
          gtk-cursor-theme-name = "volantes_cursors";
          gtk-application-prefer-dark-theme = true;
        };
      };

      home.sessionVariables = {
        QT_QPA_PLATFORMTHEME = "qt5ct";
      };

      xdg = {
        systemDirs.data = [
          "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}"
          "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
        ];

        configFile = {
          "qt5ct/qt5ct.conf" = {
            text = ''
              [Appearance]
              icon_theme=la-capitaine-icon-theme
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

          "wallpapers" = {
            source = ./wallpapers;
          };

          "kdeglobals" = {
            text = ''
              [General]
              TerminalApplication=${pkgs.foot}/bin/foot
            '';
          };
        };

        dataFile = {
          "icons/default/index.theme" = {
            text = ''
              [icon theme]
              Inherits=volantes_cursors
            '';
          };

          "icons/volantes_cursors" = {
            source = "${pkgs.jdpkgs.volantes-cursors}/usr/share/icons/volantes_cursors";
          };

          "icons/la-capitaine-icon-theme" = {
            source = "${pkgs.jdpkgs.la-capitaine-icon-theme}/share/icons/la-capitaine-icon-theme";
          };

          "icons/breeze" = {
            source = "${pkgs.breeze-icons}/share/icons/breeze";
          };

          "icons/breeze-dark" = {
            source = "${pkgs.breeze-icons}/share/icons/breeze-dark";
          };

          "icons/elementary" = {
            source = "${pkgs.pantheon.elementary-icon-theme}/share/icons/elementary";
          };

          "icons/gnome" = {
            source = "${pkgs.gnome-icon-theme}/share/icons/gnome";
          };

          "icons/hicolor" = {
            source = "${pkgs.hicolor-icon-theme}/share/icons/hicolor";
          };

          # https://wiki.archlinux.org/title/XDG_MIME_Applications#New_MIME_types
          # https://specifications.freedesktop.org/shared-mime-info-spec/shared-mime-info-spec-latest.html#idm46292897757504
          # "mime/text/x-r-markdown.xml" = {
          #   text = ''
          #     <?xml version="1.0" encoding="UTF-8"?>
          #     <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
          #       <mime-type type="text/x-r-markdown">
          #         <comment>RMarkdown file</comment>
          #         <icon name="text-x-r-markdown"/>
          #         <glob pattern="*.Rmd"/>
          #         <glob pattern="*.Rmarkdown"/>
          #       </mime-type>
          #     </mime-info>
          #   '';
          # };
        };
      };

      dconf.settings = {
        "org/gnome/desktop/interface" = {
          cursor-theme = "volantes_cursors";
          icon-theme = "la-capitaine-icon-theme";
          text-scaling-factor = 1.25;
        };
      };

      services = {
        gnome-keyring.enable = true;
      };

      xdg = {
        enable = true;
        mime.enable = true;
        mimeApps = {
          enable = true;
          associations.added = {
            "x-scheme-handler/terminal" = "foot.desktop";
            "x-scheme-handler/file" = "org.kde.dolphin.desktop";
            "x-directory/normal" = "org.kde.dolphin.desktop";
          };
          defaultApplications = {
            "application/pdf" = "okularApplication_pdf.desktop";
            "application/x-shellscript" = "nvim.desktop";
            "application/x-perl" = "nvim.desktop";
            "application/json" = "nvim.desktop";
            "text/x-readme" = "nvim.desktop";
            "text/plain" = "nvim.desktop";
            "text/markdown" = "nvim.desktop";
            "text/x-csrc" = "nvim.desktop";
            "text/x-chdr" = "nvim.desktop";
            "text/x-python" = "nvim.desktop";
            "text/x-tex" = "texstudio.desktop";
            "text/x-makefile" = "nvim.desktop";
            "inode/directory" = "org.kde.dolphin.desktop";
            "x-directory/normal" = "org.kde.dolphin.desktop";
            "x-scheme-handler/file" = "org.kde.dolphin.desktop";
            "x-scheme-handler/terminal" = "foot.desktop";
          };
        };
      };
    };
}
