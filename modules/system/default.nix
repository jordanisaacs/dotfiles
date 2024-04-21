{ inputs
, patchedPkgs
}: { pkgs
   , config
   , lib
   , ...
   }: {
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
    (import ./core { inherit inputs patchedPkgs; })
    ./impermanence
    ./greetd
    ./gnome
    ./networking
    ./graphical
    ./ssh
    ./services
    ./wireguard
    ./secrets
    ./android
    ./windows
    ./users
    ./debug
  ];
}
