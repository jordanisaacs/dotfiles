{ pkgs, config, lib, ... }:
{
  sound.enable = true;
  hardware.pulseaudio.enable = true;

  services.xserver = {
    enable = true;
    displayManager.sddm.enable = true;

    desktopManager.kde5 = {
      enable = true;
    };
  };
}

