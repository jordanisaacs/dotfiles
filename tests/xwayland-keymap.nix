{ pkgs }:
let
  profile = pkgs.xwayland.jdKeymap;
in
pkgs.runCommand "xwayland-keymap-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    COMPILER = "${profile.compiler}/bin/xkbcomp";
    ORIGINAL_COMPILER = "${profile.originalCompiler}/bin/xkbcomp";
    KEYBOARD_DATA = profile.keyboardData;
    ORIGINAL_DATA = profile.originalData;
    KEYSYM_DB = profile.keysymDB;
    KEYSYMS = builtins.toJSON profile.keysyms;
  }
  ''
    python -B ${./test_xwayland_keymap.py}
    touch "$out"
  ''
