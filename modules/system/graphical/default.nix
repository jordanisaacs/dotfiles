{
  pkgs,
  config,
  lib,
  ...
}: {
  imports = [
    ./wayland.nix
    ./xorg.nix
    ./shared.nix
  ];
}
