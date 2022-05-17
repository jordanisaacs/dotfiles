{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.work;
in {
  options.jd.work = {
    enable = mkOption {
      description = "Enable a set of common applications";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (cfg.enable) {
    targets.genericLinux.enable = true;

    home.sessionVariables = {
      MANPAGER = "sh -c 'col -bx | bat -l man -p'";
      EDITOR = "vim";
    };

    home.packages = with pkgs; [
      # Password manager
      bitwarden

      # Text editor
      neovimWork

      # CLI tools
      bat
      glow

      flameshot
      foot

      # Messaging
      slack
      kubectl

      # System Fonts
      (nerdfonts.override {fonts = ["JetBrainsMono"];})
      noto-fonts-emoji
      #openmoji-color

      # Calculator
      bc
      bitwise
    ];

    fonts.fontconfig.enable = true;

    xdg.configFile = {
      "foot/foot.ini" = {
        text = ''
          pad = 2x2 center
          font=JetBrainsMono Nerd Font Mono,Noto Color Emoji:style=Regular
        '';
      };
    };
  };
}
