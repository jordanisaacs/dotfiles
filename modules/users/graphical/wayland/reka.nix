{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.jd.graphical.wayland;
  emacsBindings = config.jd.keybindings == "emacs";
  settings = pkgs.writeText "reka-session.json" (
    builtins.toJSON {
      uiFont = config.gtk.font.name;
      uiFontSize = config.gtk.font.size;
      monospaceFont = builtins.head config.fonts.fontconfig.defaultFonts.monospace;
      nextKey = if emacsBindings then "s-n" else "s-j";
      previousKey = if emacsBindings then "s-p" else "s-k";
      launcherKey = if emacsBindings then "s-x" else "s-p";
      setup = cfg.river.setupCommand;
      commands = {
        "s-S-<return>" = [
          "${pkgs.uwsm}/bin/uwsm"
          "app"
          "-t"
          "service"
          "--"
          "${pkgs.ghostty}/bin/ghostty"
        ];
        launcher = [ "${pkgs.fuzzel}/bin/fuzzel" ];
        quit = [
          "${pkgs.uwsm}/bin/uwsm"
          "app"
          "-t"
          "service"
          "--"
          "${cfg.logout.package}/bin/desktop-logout"
        ];
        "<print>" = [ "${config.home.profileDirectory}/bin/wl-capture-region" ];
        "s-<print>" = [ "${config.home.profileDirectory}/bin/wl-capture-display" ];
        "s-S-<print>" = [ "${config.home.profileDirectory}/bin/wl-capture-displays" ];
        "<XF86AudioRaiseVolume>" = [
          "${pkgs.jdScripts.soundTools}/bin/stools"
          "vol"
          "up"
          "5"
        ];
        "<XF86AudioLowerVolume>" = [
          "${pkgs.jdScripts.soundTools}/bin/stools"
          "vol"
          "down"
          "5"
        ];
        "<XF86AudioMute>" = [
          "${pkgs.jdScripts.soundTools}/bin/stools"
          "vol"
          "toggle"
        ];
        "<XF86MonBrightnessUp>" = [
          "${pkgs.brightnessctl}/bin/brightnessctl"
          "set"
          "+4%"
        ];
        "<XF86MonBrightnessDown>" = [
          "${pkgs.brightnessctl}/bin/brightnessctl"
          "set"
          "4%-"
        ];
      };
    }
  );
in
{
  config = lib.mkIf (cfg.enable && cfg.type == "river") {
    programs.emacs = {
      enable = true;
      package = lib.mkDefault pkgs.emacs-pgtk;
      extraPackages = _: [ pkgs.reka ];
    };
    xdg.configFile."reka/init.el".text = ''
      ;;; -*- lexical-binding: t -*-
      (require 'json)
      (defconst jd-reka-settings-file ${builtins.toJSON (toString settings)})
    ''
    + builtins.readFile ../../../../scripts/reka-session.el;
  };
}
