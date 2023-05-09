{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.graphical.applications;
  isGraphical = let
    cfg = config.jd.graphical;
  in (cfg.xorg.enable == true || cfg.wayland.enable == true);

  retroArch = pkgs.retroarch.override {
    cores = with pkgs.libretro; [
      dolphin
      citra
    ];
  };
in {
  options.jd.graphical.applications.gaming = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable gaming packages";
    };
  };

  config = mkIf (isGraphical && cfg.enable && cfg.gaming.enable) {
    home.packages = [
      retroArch
    ];
  };
}
