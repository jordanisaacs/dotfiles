{ pkgs, config, lib, ... }:
{
  imports = [
    ./connectivity
    ./boot
    ./core
    ./gnome
    ./laptop
    ./framework
    ./graphical
    ./extra-container
  ];
}
