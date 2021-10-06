{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.wayland;
in
{
  options.jd.wayland = {
    enable = mkOption {
      description = "Enable wayland.";
      type = types.bool;
      default = false;
    };

    swaylock-pam = mkOption {
      description = "Enable swaylock pam";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (cfg.enable) {
    security.pam.services.swaylock = mkIf (cfg.swaylock-pam) { };
  };
}
