{ inputs }:
{ pkgs, config, lib, ... }:
{
  imports = [
    ./connectivity
    ./boot
    (import ./core { inherit inputs; })
    ./gnome
    ./laptop
    ./framework
    ./graphical
    ./extra-container
    ./ssh
    ./android
    ./windows
  ];
}
