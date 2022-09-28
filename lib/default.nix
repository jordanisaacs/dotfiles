{
  nixpkgs,
  pkgs,
  home-manager,
  system,
  lib,
  overlays,
  inputs,
  patchedPkgs,
  ...
}: rec {
  utils = pkgs.callPackage ./utils.nix {self = inputs.self;};
  user = import ./user.nix {inherit nixpkgs pkgs home-manager lib system overlays;};
  host = import ./host.nix {inherit inputs patchedPkgs user utils lib system pkgs;};
}
