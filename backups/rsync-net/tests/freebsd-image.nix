{ pkgs }:
let
  # Official signed release manifest:
  # https://www.freebsd.org/releases/14.4R/signatures/
  compressed = pkgs.fetchurl {
    url = "https://download.freebsd.org/releases/VM-IMAGES/14.4-RELEASE/amd64/Latest/FreeBSD-14.4-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2.xz";
    hash = "sha256-2Vf+VvtZYoBCgyjnjp5P6uAN02FwHKp5oGH5vSie/2c=";
  };
in
pkgs.runCommand "freebsd-14.4-release-ufs.qcow2" { nativeBuildInputs = [ pkgs.xz ]; } ''
  xz --decompress --stdout ${compressed} > "$out"
''
