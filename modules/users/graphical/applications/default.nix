{ pkgs
, config
, lib
, ...
}: {
  imports = [
    ./core.nix
    ./libreoffice.nix
    ./firefox.nix
    ./anki.nix
    ./multimedia.nix
    ./gaming.nix
    ./kdeconnect.nix
    ./dolphin.nix
    ./gnome-keyring.nix
  ];
}
