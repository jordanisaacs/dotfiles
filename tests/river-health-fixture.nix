{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "river-health-native-fixture";
  version = "1";
  dontUnpack = true;
  nativeBuildInputs = [
    pkgs.python3
    pkgs.pkg-config
    pkgs.wayland-scanner
  ];
  buildInputs = [ pkgs.wayland ];
  buildPhase = ''
    python -B ${../packages/river-health/build.py} river-health-fixture ${./river-health-fixture.c} \
      xdg=${pkgs.wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
      security=${pkgs.wayland-protocols}/share/wayland-protocols/staging/security-context/security-context-v1.xml
  '';
  dontInstall = true;
}
