{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.applications.tldr;
in
{
  options.jd.applications.tldr.enable = mkEnableOption "tldr";

  config.programs.tealdeer.enable = mkIf config.jd.applications.enable cfg.enable;
}
