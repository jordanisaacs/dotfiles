{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.desktop;
in {
  options.jd.desktop = {
    enable = mkOption {
      description = "Whether to enable desktop settings. Also tags as desktop for user settings";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (cfg.enable) {};
}
