{ pkgs, config, lib, ... }:
with lib;
{
  home.packages = with pkgs; [
    gnupg
    pinentry-curses
  ];

  services.gpg-agent = {
    enable = true;
    pinentryFlavor = "curses";
  };
}
