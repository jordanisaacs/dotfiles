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
    services = {
      # Upstream defaults to unlimited amplification. Own the tray through the
      # native service and bound ordinary scrolling at PulseAudio's unity gain.
      pasystray = {
        enable = true;
        extraOptions = [ "--volume-max=100" ];
      };
      flameshot.enable = true;
      trayscale.enable = systemCfg.networking.tailscale.enable;
    };
    # Keep desktop launch helpers available through UWSM's session environment.
    systemd.user.services.flameshot.Service.Environment = lib.mkForce [ ];

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

        # kdeconnect
        tlaplus-toolbox

        # GUI disk usage
        kdePackages.filelight

        # Utilities
        # firmware-manager - need to wait for polkit support

        (rstudioWrapper.override { packages = with rPackages; [ tidyverse ]; })

        # Logitech
        solaar
      ]
      ++ lib.optional systemCfg.networking.wifi.enable pkgs.wpa_supplicant_gui
      # The native service owns the tray; the package also supplies its launcher.
      ++ lib.optional config.services.trayscale.enable config.services.trayscale.package;

    xdg = {
      # The package also ships an uncapped XDG launcher. Only the Home Manager
      # service should own the tray, including when UWSM starts the session.
      autostart = {
        enable = true;
        entries = [
          "${pkgs.writeTextDir "pasystray.desktop" ''
            [Desktop Entry]
            Type=Application
            Name=PulseAudio System Tray
            Hidden=true
          ''}/pasystray.desktop"
        ];
      };

      desktopEntries = {
        pasystray = {
          name = "PulseAudio System Tray";
          genericName = "Audio controls";
          exec = "${pkgs.systemd}/bin/systemctl --user start pasystray.service";
          icon = "audio-card";
          terminal = false;
          categories = [
            "AudioVideo"
            "Mixer"
          ];
        };
        wifi = lib.mkIf systemCfg.networking.wifi.enable {
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
