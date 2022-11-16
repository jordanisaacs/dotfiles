{
  pkgs,
  config,
  lib,
  ...
}: {
  imports = [
    ./compositor.nix
    ./shared.nix
  ];
}
