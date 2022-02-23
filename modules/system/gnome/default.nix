{ pkgs, config, lib, ... }:
# https://nixos.wiki/wiki/GNOME#Running_GNOME_programs_outside_of_GNOME
with lib;
let
  cfg = config.jd.gnome;
in
{
  options.jd.gnome = {
    enable = mkOption {
      description = "Enable GNOME programs";
      type = types.bool;
      default = false;
    };

    keyring = {
      enable = mkOption {
        description = "Enable gnome-keyring";
        type = types.bool;
        default = false;
      };

      gui.enable = mkOption {
        description = "Enable seahorse (gnome-keyring gui)";
        type = types.bool;
        default = false;
      };
    };

  };

  config = mkIf (cfg.enable) {
    programs.dconf.enable = true;

    environment.systemPackages = with pkgs; [
    ] ++ (if cfg.keyring.enable then [
      libsecret
      jdpkgs.lssecret
    ] else [ ]);

    programs = {
      seahorse.enable = cfg.keyring.enable && cfg.keyring.gui.enable;
    };

    services.gnome = {
      gnome-keyring.enable = cfg.keyring.enable;
      # Fixes the org.a11y.Bus not provided by .service file error
      at-spi2-core.enable = true;
    };
  };
}

