{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.jd.graphical.wayland;
  isMac = config.jd.inputStyle == "mac";
  capability = config.machineData.inputRemapping or { };
  emacs = config.jd.keybindings == "emacs";
  nativeGtkBindings = ''
    @binding-set jd-mac-clipboard {
      bind "<Super>c" { "copy-clipboard" () };
      bind "<Super>x" { "cut-clipboard" () };
      bind "<Super>v" { "paste-clipboard" () };
      bind "<Super>a" {
        "move-cursor" (buffer-ends, -1, 0)
        "move-cursor" (buffer-ends, 1, 1)
      };
      bind "<Alt>Left" { "move-cursor" (words, -1, 0) };
      bind "<Alt>Right" { "move-cursor" (words, 1, 0) };
      bind "<Shift><Alt>Left" { "move-cursor" (words, -1, 1) };
      bind "<Shift><Alt>Right" { "move-cursor" (words, 1, 1) };
      bind "<Alt>BackSpace" { "delete-from-cursor" (word-ends, -1) };
      bind "<Alt>Delete" { "delete-from-cursor" (word-ends, 1) };
      bind "<Super>Left" { "move-cursor" (display-line-ends, -1, 0) };
      bind "<Super>Right" { "move-cursor" (display-line-ends, 1, 0) };
      bind "<Shift><Super>Left" { "move-cursor" (display-line-ends, -1, 1) };
      bind "<Shift><Super>Right" { "move-cursor" (display-line-ends, 1, 1) };
      bind "<Super>Up" { "move-cursor" (buffer-ends, -1, 0) };
      bind "<Super>Down" { "move-cursor" (buffer-ends, 1, 0) };
      bind "<Shift><Super>Up" { "move-cursor" (buffer-ends, -1, 1) };
      bind "<Shift><Super>Down" { "move-cursor" (buffer-ends, 1, 1) };
    }
    entry {
      -gtk-key-bindings: ${lib.optionalString emacs "gtk-emacs-text-entry, "}jd-mac-clipboard;
    }
    textview {
      -gtk-key-bindings: ${lib.optionalString emacs "gtk-emacs-text-entry, gtk-emacs-text-view, "}jd-mac-clipboard;
    }
  '';
in
{
  config = lib.mkIf (cfg.enable && isMac) {
    assertions = [
      {
        assertion = cfg.keyboard.macWmModifier != "Alt";
        message = "Alt window-management bindings collide with Mac Option word navigation and Emacs Meta editing. Choose Super+Alt or Super+Control.";
      }
      {
        assertion = (capability.capsLockAsAlt or true) == cfg.keyboard.capsLockAsAlt;
        message = "The NixOS inputRemapping Caps-to-Alt setting must match the Home Manager keyboard setting so Command+Caps retains its Option modifier.";
      }
      {
        assertion = (capability.enable or false) && lib.elem config.home.username (capability.users or [ ]);
        message = "The Mac input profile requires the NixOS inputRemapping service and an explicit allowed user; Home Manager cannot grant raw input access.";
      }
      {
        assertion = cfg.type == "river";
        message = "The Mac input profile currently supports the managed River/Oxbow and River/Reka sessions.";
      }
    ];
    gtk.gtk3.extraCss = nativeGtkBindings;
    programs.ghostty.settings.keybind = [
      "super+c=copy_to_clipboard"
      "super+v=paste_from_clipboard"
      "super+a=select_all"
      "super+w=close_surface"
      "super+q=quit"
      "super+n=new_window"
      "super+t=new_tab"
    ];
    systemd.user.services.desktop-input-bridge = {
      Unit = {
        Description = "Graphical application context for desktop Command shortcuts";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = lib.escapeShellArgs [
          "${pkgs.xremap}/bin/xremap"
          "--bridge"
          "--desktop=wlroots"
          "--no-window-logging"
          "--allow-launch=false"
        ];
        ExecCondition = "${pkgs.coreutils}/bin/test -d /run/xremap/%U";
        # The upstream bridge exits successfully when Wayland is not ready yet.
        Restart = "always";
        RestartSec = 1;
        Slice = "session.slice";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
