{
  pkgs,
  config,
  lib,
  ...
}: {
  imports = [
    ./core.nix
    ./libreoffice.nix
    ./firefox.nix
    ./anki.nix
    ./multimedia.nix
    ./kdeconnect.nix
  ];
}
