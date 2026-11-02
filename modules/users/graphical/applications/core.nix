{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.graphical;
  systemCfg = config.machineData.systemConfig;
in
{
  options.jd.graphical.applications = {
    enable = mkEnableOption "graphical applications";
  };

  config = mkIf cfg.applications.enable {
    programs = {
      emacs = {
        enable = true;
        package = pkgs.emacs-pgtk;
      };

      thunderbird.enable = true;

      chromium = {
        enable = true;
        package = pkgs.ungoogled-chromium;
      };
    };

    home.sessionVariables = {
      CALIBRE_USE_SYSTEM_THEME = "true";
    };

    home.packages =
      with pkgs;
      [
        xinput

        # jdpkgs.rstudioWrapper
        # jdpkgs.texstudioWrapper

        # updated version with wayland/grim backend
        flameshot
        libsixel

        # Password manager
        bitwarden-desktop

        # Messaging
        slack
        discord
        element-desktop

        # Reading
        calibre

        # Video conference
        zoom-us

        # Note taking
        xournalpp
        rnote

        # Sound
        pavucontrol
        pasystray

        # kdeconnect
        tlaplusToolbox

        # GUI disk usage
        kdePackages.filelight

        # Utilities
        # firmware-manager - need to wait for polkit support

        (rstudioWrapper.override { packages = with rPackages; [ tidyverse ]; })

        # Logitech
        solaar
      ]
      ++ lib.optional systemCfg.networking.wifi.enable pkgs.wpa_supplicant_gui;

    xdg = {
      desktopEntries.wifi = lib.mkIf systemCfg.networking.wifi.enable {
        name = "Wi-Fi Settings";
        genericName = "Wireless network configuration";
        exec = "${pkgs.wpa_supplicant_gui}/bin/wpa_gui -i ${
          systemCfg.networking.wifi.interface or "wlan0"
        }";
        icon = "network-wireless";
        terminal = false;
        categories = [
          "Settings"
          "Network"
        ];
      };

      desktopEntries = {
        cider = {
          name = "Cider";
          genericName = "Music Streaming";
          exec = "GDK_DPI_SCALE=1.3 cider --no-sandbox %U";
          terminal = false;
          icon = "Cider";
          type = "Application";
          categories = [
            "Audio"
            "Video"
          ];
          mimeType = [
            "x-scheme-handler/ame"
            "x-scheme-handler/cider"
            "x-scheme-handler/itms"
            "x-scheme-handler/itmss"
            "x-scheme-handler/musics"
            "x-scheme-handler/music"
          ];
        };
      };

      configFile = {
        "discord/settings.json" = {
          text = ''
            {
              "SKIP_HOST_UPDATE": true
            }
          '';
        };
      };
    };
  };
}
