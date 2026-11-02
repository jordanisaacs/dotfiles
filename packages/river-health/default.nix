{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "river-health";
  version = "1";
  dontUnpack = true;
  nativeBuildInputs = [
    pkgs.python3
    pkgs.pkg-config
    pkgs.wayland-scanner
  ];
  buildInputs = [ pkgs.wayland ];
  buildPhase = ''
    runHook preBuild
    python -B ${./build.py} river-health ${./observer.c} \
      health=${./jd-window-health-v1.xml} \
      foreign=${pkgs.wayland-protocols}/share/wayland-protocols/staging/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml
    runHook postBuild
  '';
  dontInstall = true;
  meta = {
    description = "Read-only native River application response observer";
    mainProgram = "river-health";
    platforms = pkgs.lib.platforms.linux;
    license = pkgs.lib.licenses.mit;
  };
}
