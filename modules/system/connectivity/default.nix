{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.connectivity;
in {
  options.jd.connectivity = {
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
    environment.systemPackages = with pkgs;
      optional cfg.bluetooth.enable scripts.bluetoothTools
      ++ optionals cfg.sound.enable [pulseaudio scripts.soundTools];

    security.rtkit.enable = cfg.sound.enable;
    services.pipewire = mkIf (cfg.sound.enable) {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };

    #hardware.pulseaudio.enable = cfg.sound.enable;

    services.printing.enable = cfg.printing.enable;

    hardware.bluetooth.enable = cfg.bluetooth.enable;
    services.blueman.enable = cfg.bluetooth.enable;
  };
}
