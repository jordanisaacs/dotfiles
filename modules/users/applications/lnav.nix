{ pkgs
, config
, lib
, ...
}:
with lib;
with builtins; let
  cfg = config.jd.applications.lnav;
in
{
  options.jd.applications.lnav.enable = mkEnableOption "lnav";

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      lnav
    ];

    jd.applications.readline.enable = true;
  };
}
