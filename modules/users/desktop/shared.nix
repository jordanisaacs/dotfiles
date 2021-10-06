{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.desktop;
  systemCfg = config.machineData.systemConfig;
in
{
  config = mkIf (cfg.xserver.enable == true || cfg.wayland.enable == true) {
    home.packages = with pkgs; mkIf (systemCfg.connectivity.sound.enable) [
      pavucontrol
      pasystray
    ];

    home.file = {
      "${config.xdg.configHome}/wallpapers" = {
        source = ./wallpapers;
      };
    };

    services = {
      gnome-keyring.enable = true;
    };
  };
}

