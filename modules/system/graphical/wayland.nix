{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.graphical.wayland;
in {
  options.jd.graphical.wayland = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable wayland";
    };

    swaylockPam = mkOption {
      type = types.bool;
      default = false;
      description = "Enable swaylock pam";
    };

    waylockPam = mkOption {
      type = types.bool;
      default = false;
      description = "Enable waylock pam";
    };
  };

  config = mkIf (cfg.enable) {
    xdg = {
      portal = {
        enable = true;
        wlr.enable = true;
        extraPortals = with pkgs; [
          xdg-desktop-portal-gtk
        ];
      };
    };

    # security.pam.services.swaylock = mkIf (cfg.swaylockPam) {};
    security.pam.services.swaylock = {};
    security.pam.services.waylock = mkIf (cfg.waylockPam) {};
  };
}
