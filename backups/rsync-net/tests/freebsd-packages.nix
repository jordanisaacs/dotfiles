{ pkgs }:
let
  inherit (pkgs) lib;
  # A complete dependency closure from the signed FreeBSD14 quarterly catalog.
  # The guest validates the retained upstream catalog/package signatures against
  # its release-image trust roots. Nix additionally pins every fixture byte.
  lock = builtins.fromJSON (builtins.readFile ./freebsd-packages.json);
  packages = lib.mapAttrs (
    name: item:
    pkgs.fetchurl {
      name = "${name}.pkg";
      inherit (item) url hash;
    }
  ) lock.packages;
  repository = pkgs.linkFarm "freebsd-offline-package-repository" (
    lib.mapAttrsToList (name: item: {
      name = lib.removePrefix "https://pkg.freebsd.org/FreeBSD:14:amd64/quarterly/" item.url;
      path = packages.${name};
    }) lock.packages
    ++ lib.mapAttrsToList (name: item: {
      inherit name;
      path = pkgs.fetchurl {
        name = builtins.baseNameOf name;
        inherit (item) url hash;
      };
    }) lock.repository
    ++ [
      {
        name = "Latest/pkg.pkg";
        path = packages.pkg;
      }
    ]
  );
in
pkgs.runCommand "freebsd-offline-packages.iso" { nativeBuildInputs = [ pkgs.xorriso ]; } ''
  xorriso -as mkisofs -quiet -follow-links -volid packages -joliet -rock -output "$out" ${repository}
''
