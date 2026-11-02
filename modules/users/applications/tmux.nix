{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
with builtins;
let
  cfg = config.jd.applications.tmux;

  resizeAmount = 5;
  vim = config.jd.keybindings == "vim";
  navigation =
    if vim then
      {
        left = "h";
        down = "j";
        up = "k";
        right = "l";
      }
    else
      {
        left = "b";
        down = "n";
        up = "p";
        right = "f";
      };
in
{
  options.jd.applications.tmux.enable = mkEnableOption "tmux";

  config = mkIf cfg.enable {
    programs.tmux = {
      enable = true;
      keyMode = if vim then "vi" else "emacs";
      mouse = false;
      sensibleOnTop = false;
      terminal = "screen-256color";
      secureSocket = true;
      plugins = [
        {
          plugin = pkgs.tmuxPlugins.mkTmuxPlugin {
            pluginName = "tmux-tokyo-night";
            rtpFilePath = "tmux-tokyo-night.tmux";
            version = "master";
            src = pkgs.fetchFromGitHub {
              owner = "fabioluciano";
              repo = "tmux-tokyo-night";
              rev = "156a5a010928ebae45f0d26c3af172e0425fdda8";
              sha256 = "sha256-tANO0EyXiplXPitLrwfyOEliHUZkCzDJ6nRjEVps180=";
            };
          };
          # extraConfig = ''
          #   set -g @theme_variation 'night'
          #   set -g @theme_enable_icons 1
          # '';
        }

      ];
      extraConfig = ''
        set -s escape-time 0

        bind -N "Select pane to the left of the active pane" ${navigation.left} select-pane -L
        bind -N "Select pane below the active pane" ${navigation.down} select-pane -D
        bind -N "Select pane above the active pane" ${navigation.up} select-pane -U
        bind -N "Select pane to the right of the active pane" ${navigation.right} select-pane -R

        bind -r -N "Resize the pane left by ${toString resizeAmount}" \
          ${toUpper navigation.left} resize-pane -L ${toString resizeAmount}
        bind -r -N "Resize the pane down by ${toString resizeAmount}" \
          ${toUpper navigation.down} resize-pane -D ${toString resizeAmount}
        bind -r -N "Resize the pane up by ${toString resizeAmount}" \
          ${toUpper navigation.up} resize-pane -U ${toString resizeAmount}
        bind -r -N "Resize the pane right by ${toString resizeAmount}" \
          ${toUpper navigation.right} resize-pane -R ${toString resizeAmount}

        bind -N "Split window horizontally" | split-window -h
        bind -N "Split window vertically" - split-window -v

        set -s set-clipboard off
      ''
      + (
        if vim then
          ''
            bind P paste-buffer
            bind-key -T copy-mode-vi v send-keys -X begin-selection
            bind-key -T copy-mode-vi V send-keys -X rectangle-toggle
            unbind -T copy-mode-vi Enter
            bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel '${pkgs.wl-clipboard}/bin/wl-copy'
            bind-key -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel '${pkgs.wl-clipboard}/bin/wl-copy'
            bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel '${pkgs.wl-clipboard}/bin/wl-copy'
          ''
        else
          ''
            bind C-y paste-buffer
            bind-key -T copy-mode C-Space send-keys -X begin-selection
            bind-key -T copy-mode M-w send-keys -X copy-pipe-and-cancel '${pkgs.wl-clipboard}/bin/wl-copy'
            bind-key -T copy-mode Enter send-keys -X copy-pipe-and-cancel '${pkgs.wl-clipboard}/bin/wl-copy'
            bind-key -T copy-mode MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel '${pkgs.wl-clipboard}/bin/wl-copy'
          ''
      );
    };
  };
}
