{ pkgs, config, lib, ... }:
{
  imports = [
    ../firefox
  ];

  home.sessionVariables = {
    EDITOR = "vim";
  };

  home.packages = with pkgs; [
    # Password manager
    bitwarden

    # Note taking
    obsidian
    xournalpp

    # Text editor
    neovimJD

    # File manager
    nnn
  ];
}
