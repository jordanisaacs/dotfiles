{ pkgs, homeConfiguration }:
pkgs.runCommand "river-input-device-matching"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.zig
    ];
    CHANNEL_DEPS = pkgs.river-channel.zigDeps;
    TOUCHPAD_PATTERNS = builtins.toJSON homeConfiguration.config.jd.graphical.wayland.touchpad.namePatterns;
  }
  ''
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local"
    python -B ${./test_river_input.py}
    touch "$out"
  ''
