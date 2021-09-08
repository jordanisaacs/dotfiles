{ pkgs, config, lib, ... }:

{
  imports = [
    ./applications
    ./desktop
    ./git
    ./gpg
    ./zsh
  ];
}
