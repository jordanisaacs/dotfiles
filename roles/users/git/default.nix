{ pkgs, config, lib, ...}:
{
  programs.git = {
    enable = true;
    userName = "Jordan Isaacs";
    userEmail = "github@jdisaacs.com";
  };
}

