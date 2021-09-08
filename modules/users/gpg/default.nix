{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.gpg;
in {
  options.jd.gpg = {
    enable = mkOption {
      description = "enable gpg";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (cfg.enable) {
    home.packages = with pkgs; [
      pinentry-gnome
    ];

    programs.gpg = {
      enable = true;
    };

    services.gpg-agent = {
      enable = true;
      pinentryFlavor = "gnome3";
    };
  };
}
