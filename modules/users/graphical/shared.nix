{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.graphical;
  kdeTheme =
    if cfg.theme == "arc-dark" then
      {
        package = pkgs.arc-kde-theme;
        name = "ArcDark";
      }
    else
      {
        package = pkgs.materia-kde-theme;
        name = "MateriaDark";
      };
  ini = pkgs.formats.ini { };
  qtFont = "${config.gtk.font.name},${toString config.gtk.font.size},-1,5,50,0,0,0,0,0";
  qtFixedFont = "${builtins.head config.fonts.fontconfig.defaultFonts.monospace},${toString config.gtk.font.size},-1,5,50,0,0,0,0,0";
  opaqueKvantum =
    pkgs.runCommand "opaque-${kdeTheme.name}" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        python ${./opaque-kvantum.py} "${kdeTheme.package}/share/Kvantum/${kdeTheme.name}" "$out"
      '';
in
{
  options.jd.graphical = {
    theme = mkOption {
      type =
        with types;
        enum [
          "arc-dark"
          "materia-dark"
        ];
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

  config = mkIf cfg.wayland.enable {
    home = {
      packages = with pkgs; [
        xdg-utils
        kdeTheme.package

        # Fonts
        nerd-fonts.jetbrains-mono
        nerd-fonts.monaspace
        emacs-all-the-icons-fonts
        noto-fonts-color-emoji
        roboto
        bm-font
        bm-variable-font
        noto-fonts-cjk-sans # Chinese
        dejavu_fonts
        liberation_ttf
        symbols-nerd-font # for emacs nerd-icons
        corefonts # microsoft
        carlito

        fontpreview
        emote
        #openmoji-color

        papirus-icon-theme

        seahorse
      ];
    };

    home.pointerCursor = {
      enable = true;
      package = pkgs.volantes-cursors;
      name = "volantes_cursors";
      size = cfg.cursor.size;
      # Pass through config to gtk
      # https://github.com/nix-community/home-manager/blob/693d76eeb84124cc3110793ff127aeab3832f95c/modules/config/home-cursor.nix#L152
      gtk.enable = true;
    };

    fonts.fontconfig = {
      enable = true;
      defaultFonts = {
        sansSerif = [ config.gtk.font.name ];
        serif = [ "Noto Serif" ];
        monospace = [
          "Berkeley Mono Variable"
          "DejaVu Sans Mono"
        ];
        emoji = [ "Noto Color Emoji" ];
      };
    };

    qt = {
      enable = true;
      # KDE applications' color-scheme manager requires a platform theme that
      # reports the desktop dark preference, independently of the widget style.
      platformTheme.name = "kde";
      style.name = "kvantum";
    };

    gtk = {
      gtk4.theme = config.gtk.theme;
      gtk3.extraConfig = {
        gtk-application-prefer-dark-theme = true;
        gtk-key-theme-name = if config.jd.keybindings == "emacs" then "Emacs" else "Default";
      };
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
        name = "Papirus-Dark";
      };

      font = {
        package = pkgs.noto-fonts;
        name = "Noto Sans";
        # Shared GUI font: Qt's KDE palette/fonts and Waybar derive from this.
        # Terminal and launcher fonts have their own explicit sizing policies.
        size = 15;
      };
    };

    xdg = {
      # Home Manager starts all keyring components in one user service. The
      # package also ships two XDG launchers, which otherwise initialize the
      # same daemon again when UWSM starts graphical-session.target.
      autostart = mkIf config.services.gnome-keyring.enable {
        enable = true;
        entries =
          map
            (
              component:
              let
                filename = "gnome-keyring-${component}.desktop";
                entry = pkgs.writeTextDir filename ''
                  [Desktop Entry]
                  Type=Application
                  Name=GNOME Keyring (${component})
                  Hidden=true
                '';
              in
              "${entry}/${filename}"
            )
            [
              "pkcs11"
              "secrets"
            ];
      };

      systemDirs.data = [
        "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}"
        "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
      ];

      configFile = {
        "fontconfig/conf.d/04-font-priority.conf" =
          let
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

        "Kvantum/kvantum.kvconfig" = {
          text = "theme=${kdeTheme.name}";
        };

        "Kvantum/${kdeTheme.name}" = {
          source = opaqueKvantum;
        };

        "wallpapers" = {
          source = ./wallpapers;
        };

        "kdeglobals" = {
          # KDE applications read their own color roles independently of the
          # Qt widget style. Install the matching palette, including text colors.
          source = pkgs.concatText "kdeglobals" [
            "${kdeTheme.package}/share/color-schemes/${kdeTheme.name}.colors"
            (ini.generate "kdeglobals-settings" {
              General = {
                TerminalApplication = "${pkgs.ghostty}/bin/ghostty";
                font = qtFont;
                fixed = qtFixedFont;
                menuFont = qtFont;
                smallestReadableFont = qtFont;
                toolBarFont = qtFont;
              };
              Icons.Theme = "Papirus-Dark";
              KDE = {
                ShowDeleteCommand = false;
                widgetStyle = "kvantum";
              };
              PreviewSettings.MaximumRemoteSize = 0;
            })
          ];
        };
      };
    };

    # dconf settings set by gtk settings: https://github.com/nix-community/home-manager/blob/693d76eeb84124cc3110793ff127aeab3832f95c/modules/misc/gtk.nix#L227
    dconf.settings = {
      "org/gnome/desktop/interface" = {
        # https://askubuntu.com/questions/1404764/how-to-use-hdystylemanagercolor-scheme
        color-scheme = "prefer-dark";
        text-scaling-factor = 1.0;
        cursor-size = cfg.cursor.size;
      };
    };

    services.gnome-keyring.enable = config.machineData.systemConfig.gnome.keyring.enable;
  };
}
