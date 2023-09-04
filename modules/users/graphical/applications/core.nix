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
  options.jd.graphical.applications = {
    enable = mkEnableOption "graphical applications";
  };

  config = mkIf cfg.applications.enable {
    home.packages = with pkgs;
      [
        xorg.xinput

        thunderbird
        # jdpkgs.rstudioWrapper
        # jdpkgs.texstudioWrapper
        ungoogled-chromium

        # updated version with wayland/grim backend
        jdpkgs.flameshot
        libsixel

        # Password manager
        bitwarden
        jdpkgs.authy

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

        # music
        cider

        # kdeconnect

        # Utilities
        # firmware-manager - need to wait for polkit support

        (rstudioWrapper.override {
          packages = with rPackages; [tidyverse];
        })
      ]
      ++ lib.optional systemCfg.networking.wifi.enable pkgs.iwgtk;

    xdg.desktopEntries = {
      cider = {
        name = "Cider";
        genericName = "Music Streaming";
        exec = "GDK_DPI_SCALE=1.3 cider --no-sandbox %U";
        terminal = false;
        icon = "Cider";
        type = "Application";
        categories = ["Audio" "Video"];
        mimeType = ["x-scheme-handler/ame" "x-scheme-handler/cider" "x-scheme-handler/itms" "x-scheme-handler/itmss" "x-scheme-handler/musics" "x-scheme-handler/music"];
      };
    };

    xdg.configFile = {
      "discord/settings.json" = {
        text = ''
          {
            "SKIP_HOST_UPDATE": true
          }
        '';
      };
    };
  };
}
