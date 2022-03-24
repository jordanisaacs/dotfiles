{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.graphical;
in
{
  options.jd.graphical.applications = {
    enable = mkOption {
      type = types.bool;
      description = "Enable graphical applications";
    };
  };

  config = {
    home.packages = with pkgs; [
      dolphin
      discord
      okular

      jdpkgs.rstudioWrapper
      jdpkgs.texstudioWrapper

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
