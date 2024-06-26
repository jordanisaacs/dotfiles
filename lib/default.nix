{ nixpkgs
, pkgs
, home-manager
, system
, lib
, overlays
, inputs
, patchedPkgs
, ...
}: rec {
  utils = pkgs.callPackage ./utils.nix { inherit (inputs) self; };
  user = import ./user.nix { inherit nixpkgs pkgs home-manager lib system overlays inputs; };
  host = import ./host.nix { inherit inputs patchedPkgs user utils lib system pkgs; };
}
