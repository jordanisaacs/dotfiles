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
    ./shell
    ./ssh
    ./office365
    ./wine
    ./keybase
    ./pijul
    ./secrets
    ./weechat
    ./impermanence
    ./kernel
  ];
}
