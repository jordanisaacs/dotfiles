{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.connectivity;
in
{
  options.jd.connectivity = {
    wifi.enable = mkOption {
      description = "Enable wifi with default options";
      type = types.bool;
      default = false;
    };

    bluetooth.enable = mkOption {
      description = "Enable bluetooth with default options";
      type = types.bool;
      default = false;
    };

    printing.enable = mkOption {
      description = "Enable printer";
      type = types.bool;
      default = false;
    };

    sound.enable = mkOption {
      description = "Enable sound";
      type = types.bool;
      default = false;
    };
  };

  config = {
    environment.systemPackages = with pkgs; [
    ] ++ (if (cfg.bluetooth.enable) then [
      scripts.bluetoothTools
    ] else [ ]) ++ (if (cfg.sound.enable) then [
      pulseaudio
      scripts.soundTools
    ] else [ ]);

    networking.wireless.enable = cfg.wifi.enable;

    security.rtkit.enable = cfg.sound.enable;
    services.pipewire = {
      enable = cfg.sound.enable;
      alsa.enable = cfg.sound.enable;
      alsa.support32Bit = cfg.sound.enable;
      pulse.enable = cfg.sound.enable;
    };

    #hardware.pulseaudio.enable = cfg.sound.enable;

    services.printing.enable = cfg.printing.enable;

    hardware.bluetooth = {
      enable = cfg.bluetooth.enable;
    };

    services.blueman.enable = true;
  };
}
