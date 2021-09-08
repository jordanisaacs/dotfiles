{ config, pkgs, lib, ... }:
{
  hardware.pulseaudio.enable = true;

  services.xserver = {
    enable = true;
    libinput = {
      enable = true;
      touchpad = {
        naturalScrolling = true;
      };
    };
    displayManager.startx.enable = true;
  };

  environment.etc = {
    # Makes an /etc/profile.local sourced by /etc/profile
    "profile.local".text = ''
      # /etc/profile.local: DO NOT EDIT -- this file has been generated automatically.
      if [ -f "$HOME/.profile" ]; then
        . "$HOME/.profile"
      fi
      if [ -z "$DISPLAY" ] && [ $TTY == "/dev/tty1" ]; then
        exec startx
      fi
    '';
  };
}
