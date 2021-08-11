{ pkgs, config, lib, ... }:
{
  home.sessionVariables = {
    EDITOR = "vim";
  };

  home.packages = with pkgs; [
    firefox
    bitwarden
    obsidian
    neovimJD
    xournalpp
  ];
}
