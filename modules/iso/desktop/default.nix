{ pkgs, config, lib, ... }:
with lib; {
  options.jd = { sound = mkEnableOption "sound"; };

  config = {
    hardware.pulseaudio.enable = config.jd.sound;

    services.displayManager.sddm.enable = true;
    services.displayManager.sddm.wayland.enable = true;
    services.desktopManager.plasma6.enable = true;
  };
}
