{ pkgs, config, lib, ... }:

{
  imports = [
    ./applications
    ./wayland.nix
    ./xorg.nix
    ./shared.nix
    ./config.nix
  ];
}
