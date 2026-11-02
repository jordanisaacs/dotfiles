{ config, lib, ... }:
with lib;
{
  options.jd = {
    sound = mkEnableOption "sound";
  };

  config = {
    hardware.pulseaudio.enable = config.jd.sound;

    services = {
      displayManager.sddm.enable = true;

      displayManager.sddm.wayland.enable = true;

      desktopManager.plasma6.enable = true;
    };
  };
}
