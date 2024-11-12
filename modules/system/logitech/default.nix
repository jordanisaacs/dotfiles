{ pkgs, config, lib, ... }:
with lib;
let cfg = config.jd.logitech;
in {
  options.jd.logitech = { enable = mkEnableOption "logitech"; };

  config = mkIf cfg.enable { hardware.logitech.wireless.enable = true; };
}
