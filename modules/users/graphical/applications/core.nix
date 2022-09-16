{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.graphical;
in {
  options.jd.graphical.applications = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable graphical applications";
    };
  };

  config = mkIf (cfg.applications.enable) {
    home.packages = with pkgs; [
      jdpkgs.dolphin # fixes dbus/firefox
      okular
      wdisplays

      thunderbird
      jdpkgs.rstudioWrapper
      jdpkgs.texstudioWrapper
      jdpkgs.microsoft-edge-stable

      flameshot
      libsixel

      # Password manager
      bitwarden
      authy

      # Messaging
      slack
      discord

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
    ];

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
