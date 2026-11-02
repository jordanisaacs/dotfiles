{ inputs }:
{ ... }:
{
  # Not all modules are imported here
  # some are modules that are reliant on non nixos modules.
  # Thus imported at top level in lib/mkhost
  imports = [
    ./fs
    ./kernel
    ./boot
    ./initrd

    ./laptop
    ./desktop
    ./framework

    ./connectivity
    ./extraContainer
    (import ./core { inherit inputs; })
    ./impermanence
    ./greetd
    ./gnome
    ./networking
    ./graphical
    ./ssh
    ../../backups/rsync-net/client/nixos.nix
    ./services
    ./wireguard
    ./secrets
    ./android
    ./windows
    ./users
    ./debug
    ./logitech
    ./qmk
  ];
}
