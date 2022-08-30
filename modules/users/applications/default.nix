{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.applications;
in {
  options.jd.applications = {
    enable = mkOption {
      description = "Enable a set of common applications";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (cfg.enable) {
    home.sessionVariables = {
      MANPAGER = "sh -c 'col -bx | bat -l man -p'";
      EDITOR = "vim";
    };

    home.packages = with pkgs; [
      # Password manager
      bitwarden

      # Note taking
      obsidian #knowledge base
      xournalpp #drawing

      # Text editor
      neovimJD

      # ssh mount
      sshfs

      # Deployment tools
      deploy-rs
      agenix-cli

      # CLI tools
      bat
      glow
      nnn # file manager
      grit # to-do
      buku # bookmarks
      yt-dlp

      # Dev tools
      alejandra # nix formatting

      # Messaging
      slack

      # Video conference
      zoom-us

      # Productivity Suite
      pdftk

      # System Fonts
      (nerdfonts.override {fonts = ["JetBrainsMono"];})
      noto-fonts-emoji
      #openmoji-color

      # Typing fonts
      carlito

      # Calculator
      bc
      bitwise
    ];

    fonts.fontconfig.enable = true;

    programs.mpv = {
      enable = true;
      config = {
        profile = "gpu-hq";
        vo = "gpu";
        hwdec = "auto-safe";
        ytdl-format = "ytdl-format=bestvideo[height<=?1920][fps<=?30][vcodec!=?vp9]+bestaudio/best";
      };
    };
  };
}
