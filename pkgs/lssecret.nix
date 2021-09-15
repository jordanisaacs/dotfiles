{ pkgs, ... }:
with pkgs;
stdenv.mkDerivation rec {
  pname = "lssecret";
  version = "1.0.0";
  src = builtins.fetchTarball {
    url = "https://gitlab.com/GrantMoyer/lssecret/-/archive/master/lssecret-master.tar.gz";
    sha256 = "1pm26anwy0l6v6xjgs7yiijvq7jmmdk3ngpp9xhvz84jgi2p3fr8";
  };
  buildInputs = [ libsecret pkg-config ];
  buildPhase = ''
    make
  '';
  installPhase = ''
    DESTDIR=$out make install
  '';
}
