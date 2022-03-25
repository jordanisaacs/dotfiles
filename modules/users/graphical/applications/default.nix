{ pkgs, config, lib, ... }:

{
  imports = [
    ./core.nix
    ./libreoffice.nix
    ./firefox.nix
    ./multimedia.nix
  ];
}
