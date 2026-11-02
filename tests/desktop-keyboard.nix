{ pkgs, homeConfiguration }:
let
  keyboard = homeConfiguration.config.jd.graphical.wayland.keyboard;
in
pkgs.runCommand "desktop-keyboard-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    LIBXKB = "${pkgs.lib.getLib pkgs.libxkbcommon}/lib/libxkbcommon.so.0";
    KEYMAP = keyboard.keymap;
    XKB_EXTENSION = keyboard.xkbDirectory;
    LAYOUT = keyboard.layout;
    VARIANT = keyboard.variant;
    OPTIONS = builtins.toJSON keyboard.options;
    CAPS_ALT = builtins.toJSON keyboard.capsLockAsAlt;
  }
  ''
    python -B ${./test_desktop_keyboard.py}
    touch "$out"
  ''
