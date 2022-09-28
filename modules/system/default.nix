{
  inputs,
  patchedPkgs,
}: {
  pkgs,
  config,
  lib,
  ...
}: {
  # Not all modules are imported here
  # some are modules that are reliant on non nixos modules.
  # Thus imported at top level in lib/mkhost
  imports = [
    ./connectivity
    ./boot
    ./extraContainer
    (import ./core {inherit inputs patchedPkgs;})
    ./greetd
    ./gnome
    ./networking
    ./laptop
    ./framework
    ./graphical
    ./ssh
    ./services
    ./wireguard
    ./secrets
    ./android
    ./windows
    ./desktop
  ];
}
