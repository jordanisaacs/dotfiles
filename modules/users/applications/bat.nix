{ pkgs
, config
, lib
, ...
}:
with lib;
with builtins; let
  cfg = config.jd.applications.bat;
in
{
  options.jd.applications.bat = {
    enable = mkEnableOption "a set of common non-graphical applications";

    man = mkEnableOption "Use bat for rendering manpages";
  };

  config = mkIf cfg.enable {
    home.sessionVariables = mkIf cfg.man {
      MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    };

    programs.bat.enable = true;
  };
}
