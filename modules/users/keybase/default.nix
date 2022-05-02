{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.keybase;
in {
  options.jd.keybase = {
    enable = mkOption {
      description = "Enable keybase";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    home.packages = [pkgs.keybase-gui];
    services.kbfs.enable = true;
  };
}
