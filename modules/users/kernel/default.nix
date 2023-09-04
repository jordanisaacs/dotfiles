{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.kernel;
in
{
  # Based on https://josefbacik.github.io/kernel/2021/10/18/lei-and-b4.html
  options.jd.kernel.enable = mkEnableOption "kernel development workflow";

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      b4
      public-inbox # lei
      msmtp
      mblaze
    ];
  };
}
