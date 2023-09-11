{ pkgs
, config
, lib
, ...
}:
with lib;
{
  options.jd = {
    sound = mkEnableOption "sound";
  };

  config = {
    sound.enable = config.jd.sound;
    hardware.pulseaudio.enable = config.jd.sound;

    services.xserver = {
      enable = true;
      displayManager.sddm.enable = true;

      desktopManager.plasma5 = {
        enable = true;
      };
    };
  };
}
