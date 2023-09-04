{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.graphical.applications;
  isGraphical =
    let
      cfg = config.jd.graphical;
    in
    cfg.xorg.enable || cfg.wayland.enable;

  retroArch = pkgs.retroarch.override {
    cores = with pkgs.libretro; [
      dolphin
      citra
    ];
  };
in
{
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
