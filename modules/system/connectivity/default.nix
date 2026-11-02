{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.connectivity;
in
{
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
    environment.systemPackages =
      with pkgs;
      optional cfg.bluetooth.enable jdScripts.bluetoothTools
      ++ optionals cfg.sound.enable [
        pulseaudio
        jdScripts.soundTools
      ];

    security.rtkit.enable = cfg.sound.enable;
    services = {
      pipewire = mkIf cfg.sound.enable {
        enable = true;
        # Capture allocation is negotiated by the server. Keep client libraries
        # on the upstream package to avoid rebuilding unrelated applications.
        package = pkgs.pipewire-capture;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
        jack.enable = true;
        # Audio must survive Xwayland/compositor restarts. The optional X11
        # bell module otherwise keeps an X connection in the audio daemon.
        extraConfig.pipewire."10-no-x11-bell"."context.properties"."module.x11.bell" = false;
      };

      printing.enable = cfg.printing.enable;

      blueman.enable = cfg.bluetooth.enable;
    };

    hardware.bluetooth.enable = cfg.bluetooth.enable;

    # NixOS creates /etc/bluetooth and manages its config files. BlueZ's unit
    # also declares ConfigurationDirectory with a different mode, causing a
    # warning at every start. Leave this directory to the NixOS /etc owner;
    # ProtectSystem=strict still makes it read-only to the daemon.
    systemd.services.bluetooth.serviceConfig.ConfigurationDirectory = mkIf cfg.bluetooth.enable (
      mkForce ""
    );
  };
}
