{ config, pkgs, ... }:

{
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "jd";
  home.homeDirectory = "/home/jd";

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "21.05";


  nixpkgs.config.allowUnfree = true;

  fonts.fontconfig.enable = true;

  programs.firefox = {
    enable = true;
    extension = with pkgs.nur.repos.rycee.firef
  };

  home.packages = with pkgs; [
    alacritty
    obsidian
    bitwarden
    git-crypt
    discord
    (nerdfonts.override { fonts = [ "FiraCode" ]; })
  ];

  home.file = {
    ".config/alacritty/alacritty.yaml".text = ''
      env:
        TERM: xterm-256color
    '';
  };
}
