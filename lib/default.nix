{
  pkgs,
  home-manager,
  system,
  lib,
  inputs,
  ...
}:
rec {
  utils = pkgs.callPackage ./utils.nix { inherit (inputs) self; };
  user = import ./user.nix {
    inherit pkgs home-manager inputs;
  };
  host = import ./host.nix {
    inherit
      inputs
      utils
      lib
      system
      pkgs
      ;
  };
}
