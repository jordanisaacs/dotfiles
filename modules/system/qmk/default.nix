{ pkgs, config, lib, ... }:
with lib;
let cfg = config.jd.qmk;
in {
  options.jd.qmk = { enable = mkEnableOption "qmk"; };

  config = mkIf cfg.enable { hardware.keyboard.qmk.enable = true; };
}
