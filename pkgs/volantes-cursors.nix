{ pkgs, ... }:
with pkgs;
stdenv.mkDerivation rec {
  pname = "volantes-cursors";
  version = "1.0.0";
  src = builtins.fetchTarball {
    url = "https://github.com/varlesh/volantes-cursors/archive/d1d290ff42cc4fa643716551bd0b02582b90fd2f.tar.gz";
    sha256 = "1nhga1h0gn8azalsmgja2sz1v1k6kkj4ivxpc0kxv8z8x7yhvcwa";
  };
  buildInputs = [ inkscape xorg.xcursorgen ];
  buildPhase = ''
    make build
  '';
  installPhase = ''
    DESTDIR=$out make install
  '';
}
