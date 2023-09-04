{ pkgs
, config
, lib
, ...
}: {
  sound.enable = true;
  hardware.pulseaudio.enable = true;

  services.xserver = {
    enable = true;
    displayManager.sddm.enable = true;

    desktopManager.plasma5 = {
      enable = true;
    };
  };
}
