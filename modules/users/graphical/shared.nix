{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.graphical;
  systemCfg = config.machineData.systemConfig;
in
{
  config = mkIf (cfg.xorg.enable == true || cfg.wayland.enable == true)
    {
      home.packages = with pkgs; mkIf (systemCfg.connectivity.sound.enable) [
        calibre
        pavucontrol
        pasystray
        myPkgs.volantes-cursors
        authy
        spotify

      ];

      home.file = {
        "${config.xdg.configHome}/wallpapers" = {
          source = ./wallpapers;
        };

        ".icons/default/index.theme" = {
          text = ''
            [icon theme]
            Inherits=volantes_cursors
          '';
        };

        ".icons/volantes_cursors" = {
          source = "${pkgs.myPkgs.volantes-cursors}/usr/share/icons/volantes_cursors";
        };
      };

      gtk = {
        enable = true;
        theme = {
          package = with pkgs; arc-theme;
          name = "Arc-Dark";
        };
        gtk3.extraConfig = {
          gtk-cursor-theme-name = "volantes_cursors";
          gtk-application-prefer-dark-theme = true;
        };
      };

      xdg.systemDirs.data = [
        "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}"
        "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
      ];

      dconf.settings = {
        "org/gnome/desktop/interface" = {
          cursor-theme = "volantes_cursors";
          text-scaling-factor = 1.25;
          icon-theme = "Arc-Dark";
        };
      };

      services = {
        gnome-keyring.enable = true;
      };
    };
}




