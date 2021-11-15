{ pkgs, config, lib, ... }:
with lib;

{
  config.jd.graphical = {
    wayland = {
      enable = mkDefault false;
      type = mkDefault null;

      background = {
        enable = mkDefault false;
        image = mkDefault ./wallpapers/peacefulmtn.jpg;
        mode = mkDefault "fill";
        pkg = mkDefault pkgs.swaybg;
      };

      screenlock = {
        enable = mkDefault false;
      };
    };
  };
}
