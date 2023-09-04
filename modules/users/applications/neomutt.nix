{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.applications.neomutt;
in
{
  options.jd.applications.neomutt = {
    enable = mkOption {
      description = "Enable neomutt";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (config.jd.applications.enable && cfg.enable) {
    programs.neomutt = {
      enable = true;
    };
  };
}
