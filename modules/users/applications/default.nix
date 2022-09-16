{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.applications;
in {
  imports = [
    ./taskwarrior
    ./direnv
  ];

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

    # TTY compatible CLI applications
    home.packages = with pkgs; [
      home-manager

      # Text editor
      neovimJD

      # ssh mount
      sshfs

      # CLI tools
      glow
      nnn # file manager
      grit # to-do
      buku # bookmarks
      yt-dlp
      # Productivity Suite
      pdftk

      # System Fonts
      (nerdfonts.override {fonts = ["JetBrainsMono"];})
      noto-fonts-emoji
      #openmoji-color

      # Typing fonts
      carlito

      # terminal session recorder
      asciinema

      # terminal art
      pipes-rs
      cbonsai
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
