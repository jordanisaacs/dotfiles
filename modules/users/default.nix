{
  pkgs,
  config,
  lib,
  ...
}: {
  imports = [
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
  ];
}
