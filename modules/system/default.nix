{ pkgs, config, lib, ... }:
{
  imports = [
    ./connectivity
    ./boot
    ./core
    ./desktop-xorg
    ./gnome
    ./laptop
  ];
}
