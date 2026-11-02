{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.graphical.wayland;
in
{
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

  config = mkIf cfg.enable {
    # Use upstream session units, D-Bus broker and environment cleanup.
    programs.uwsm.enable = true;
    security.pam.services.swaylock = { };
    security.pam.services.waylock = mkIf cfg.waylockPam { };
  };
}
