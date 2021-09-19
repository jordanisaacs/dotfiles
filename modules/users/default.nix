{ pkgs, config, lib, ... }:

{
  imports = [
    ./applications
    ./desktop
    ./git
    ./gpg
    ./zsh
    ./ssh
    ./office365
  ];
}
