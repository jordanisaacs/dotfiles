{ pkgs, config, lib, ...  }:
with lib;
let
  cfg = config.jd.keyring;
in {
  options.jd.keyring = {
    enable = mkOption {
      description = "Enable gnome-keyring";
      type = types.bool;
      default = false;
    };

    gui = {
      enable = mkOption {
        description = "Enable gui for gnome-keyring [seahorse]";
        type = types.bool;
        default = false;
      };
    };
  };

  config = mkIf (cfg.enable) {
    environment.systemPackages = with pkgs; [
      libsecret
    ];

    programs = {
      seahorse.enable = cfg.gui.enable;
    };

    services = {
      gnome.gnome-keyring.enable = true;
    };
  };
}

