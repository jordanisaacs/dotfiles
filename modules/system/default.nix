{inputs}: {
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
    (import ./core {inherit inputs;})
    ./greetd
    ./gnome
    ./networking
    ./laptop
    ./framework
    ./graphical
    ./ssh
    ./miniflux
    ./wireguard
    ./secrets
    ./android
    ./windows
    ./desktop
  ];
}
