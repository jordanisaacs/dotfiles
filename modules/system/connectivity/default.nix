{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.connectivity;
in {
  options.jd.connectivity = {
    wifi.enable = mkOption {
      description = "Enable wifi with default options";
      type = types.bool;
      default = true;
    };

    bluetooth.enable = mkOption {
      description = "Enable bluetooth with default options";
      type = types.bool;
      default = true;
    };

    printer.enable = mkOption {
      description = "Enable printer";
      type = types.bool;
      default = true;
    };
  };

  config = {
    environment.systemPackages = with pkgs; [ pulseaudio ];
    networking.wireless.enable = cfg.wifi.enable;

    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    services.printing.enable = true;

    hardware.bluetooth.enable = cfg.bluetooth.enable;
    services.blueman.enable = cfg.bluetooth.enable;
  };
}
