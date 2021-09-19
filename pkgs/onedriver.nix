{ pkgs, ... }:
with pkgs;
# broken currently
let
in buildGoModule rec {
  pname = "onedriver";
  version = "0.11.2";
  src = builtins.fetchTarball {
    url = "https://github.com/jstaf/onedriver/archive/refs/tags/v0.11.2.tar.gz";
    sha256 = "1w6524jn68knn9079i1bv6vvv3n9pbx4vf9lbvlipglb9mns0bzv";
  };
  vendorSha256 = "d2Y+jlj0wIOU9UvE79qNmYh5EXnnJbehmXWQKoXZEqY=";
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ go gcc json-glib webkitgtk ];
}
