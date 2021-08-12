{ pkgs, config, lib, ... }:
let
  args = {
    inherit lib;
    startCommand = "${pkgs.dwm}/bin/dwm";
  };

  login = (import ../shared/login.nix) args;
in lib.recursiveUpdate {
  home.packages = with pkgs; [
    dwm st
  ];} login


