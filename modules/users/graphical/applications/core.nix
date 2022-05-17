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
      dolphin
      discord
      okular
      wdisplays

      jdpkgs.rstudioWrapper
      jdpkgs.texstudioWrapper
      jdpkgs.microsoft-edge-stable

      flameshot
      libsixel
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
