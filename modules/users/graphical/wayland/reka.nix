{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.jd.graphical.wayland;
  emacsBindings = config.jd.keybindings == "emacs";
  inputProfile = import ../../../../lib/input-profile.nix {
    style = config.jd.inputStyle;
    wmModifier = cfg.keyboard.macWmModifier;
  };
  wm = inputProfile.emacsWmModifier;
  settings = pkgs.writeText "reka-session.json" (
    builtins.toJSON {
      uiFont = config.gtk.font.name;
      uiFontSize = config.gtk.font.size;
      monospaceFont = builtins.head config.fonts.fontconfig.defaultFonts.monospace;
      nextKey = wm + (if emacsBindings then "n" else "j");
      previousKey = wm + (if emacsBindings then "p" else "k");
      launcherKey =
        if inputProfile.isMac then
          inputProfile.emacsLauncher
        else
          wm + (if emacsBindings then "x" else "p");
      inherit (inputProfile) isMac;
      nextWindowKey = inputProfile.emacsNextWindow;
      previousWindowKey = inputProfile.emacsPreviousWindow;
      floatingKey = wm + "SPC";
      closeKey = wm + "S-c";
      monocleKey = wm + "m";
      balanceKey = wm + "t";
      workspacePrefix = wm;
      fullscreenKey = inputProfile.emacsFullscreen;
      setup = cfg.river.setupCommand;
      commands = {
        "${wm}S-<return>" = [
          "${pkgs.uwsm}/bin/uwsm"
          "app"
          "-t"
          "service"
          "--"
          "${pkgs.ghostty}/bin/ghostty"
        ];
        launcher = [ "${pkgs.fuzzel}/bin/fuzzel" ];
        "${wm}v" = [
          "${pkgs.uwsm}/bin/uwsm"
          "app"
          "-t"
          "service"
          "--"
          "${cfg.clipboard.package}/bin/clipboard-history"
          "pick"
        ];
        "${wm}S-v" = [
          "${config.services.swaync.package}/bin/swaync-client"
          "--toggle-panel"
          "--skip-wait"
        ];
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
      }
      // lib.optionalAttrs inputProfile.isMac {
        "s-S-3" = [ "${config.home.profileDirectory}/bin/wl-capture-displays" ];
        "s-S-4" = [ "${config.home.profileDirectory}/bin/wl-capture-region" ];
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
