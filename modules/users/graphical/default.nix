{ pkgs
, config
, lib
, ...
}: {
  imports = [
    ./applications
    ./wayland
    ./xorg.nix
    ./shared.nix
    ./config.nix
  ];
}
