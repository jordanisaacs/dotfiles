{
  pkgs,
  config,
  lib,
  ...
}: {
  imports = [
    ./core
    ./applications
    ./graphical
    ./git
    ./gpg
    ./zsh
    ./ssh
    ./office365
    ./wine
    ./keybase
    ./pijul
    ./secrets
    ./weechat
    ./impermanence
  ];
}
