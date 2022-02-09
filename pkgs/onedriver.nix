{ pkgs, ... }:
with pkgs;
# broken currently
let
  program = buildGoModule
    rec {
      pname = "onedriver";
      version = "0.12.0";
      src = builtins.fetchTarball {
        url = "https://github.com/jstaf/onedriver/archive/refs/tags/v0.12.0.tar.gz";
        sha256 = "133x6vk3ks5iwqjk0czdg6c0vjaqx7i34imxa1y2k34j3ll4kq9a";
      };
      vendorSha256 = "vHmSmluiJdfIvVyAc7Um9v+1I50AGGIYw6la9w8rNso=";
      nativeBuildInputs = [ pkg-config glib-networking ];
      buildInputs = [ go gcc json-glib webkitgtk ];
      doCheck = false; # fails GUI test
    };

  # Need to wrap to set the glib-networking directory
  # https://www.reddit.com/r/NixOS/comments/k1lt7c/tlsssl_support_not_available_install/
  onedriverWrapper = pkgs.runCommand "onedriverWrapper"
    {
      buildInputs = [ pkgs.makeWrapper ];
    }
    (
      ''
        mkdir -p $out/bin

        makeWrapper ${program}/bin/onedriver $out/bin/onedriver --set GIO_MODULE_DIR ${glib-networking}/lib/gio/modules
      ''
    );
in
onedriverWrapper
