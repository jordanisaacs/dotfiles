{
  pkgs,
  home-manager,
  system,
  lib,
  overlays,
  inputs,
  ...
}: let
  utils = pkgs.callPackage ./utils.nix {self = inputs.self;};
in rec {
  user = import ./user.nix {inherit pkgs home-manager lib system overlays;};
  host = import ./host.nix {inherit inputs user utils lib system pkgs;};
}
