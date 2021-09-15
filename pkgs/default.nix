{ pkgs, ... }:
with pkgs;
{
  myPkgs = {
    lssecret = callPackage ./lssecret.nix { };
  };
}
