{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
with builtins; let
  cfg = config.jd.applications;
in {
  options.jd.applications.bat = {
    enable = mkEnableOption "a set of common non-graphical applications";

    man = mkEnableOption "Use bat for rendering manpages";
  };

  config = mkIf (cfg.enable && cfg.bat.enable) {
    home.sessionVariables = mkIf cfg.bat.man {
      MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    };

    programs.bat.enable = true;
  };
}
