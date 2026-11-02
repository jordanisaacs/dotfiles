{ pkgs }:
pkgs.runCommand "initrd-dlopen-alternatives-tests"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.stdenv.cc
      pkgs.binutils
    ];
    INITRD_TOOL = pkgs.lib.getExe pkgs.makeInitrdNGTool;
  }
  ''
    python -B ${./test_initrd_dlopen.py}
    touch "$out"
  ''
