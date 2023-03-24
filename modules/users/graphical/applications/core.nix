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
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable graphical applications";
    };
  };

  config = mkIf (cfg.applications.enable) {
    home.packages = with pkgs;
      [
        dolphin # fixes dbus/firefox
        okular
        xorg.xinput

        thunderbird
        # jdpkgs.rstudioWrapper
        # jdpkgs.texstudioWrapper
        microsoft-edge

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
      ]
      ++ lib.optional systemCfg.networking.wifi.enable pkgs.iwgtk;

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
