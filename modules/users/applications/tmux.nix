{ pkgs
, config
, lib
, ...
}:
with lib;
with builtins; let
  cfg = config.jd.applications.tmux;

  resizeAmount = 5;
in
{
  options.jd.applications.tmux.enable = mkEnableOption "tmux";

  config = mkIf cfg.enable {
    programs.tmux = {
      enable = true;
      keyMode = "vi";
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

        bind -N "Select pane to the left of the active pane" h select-pane -L
        bind -N "Select pane below the active pane" j select-pane -D
        bind -N "Select pane above the active pane" k select-pane -U
        bind -N "Select pane to the right of the active pane" l select-pane -R

        bind -r -N "Resize the pane left by ${toString resizeAmount}" \
          H resize-pane -L ${toString resizeAmount}
        bind -r -N "Resize the pane down by ${toString resizeAmount}" \
          J resize-pane -D ${toString resizeAmount}
        bind -r -N "Resize the pane up by ${toString resizeAmount}" \
          K resize-pane -U ${toString resizeAmount}
        bind -r -N "Resize the pane right by ${toString resizeAmount}" \
          L resize-pane -R ${toString resizeAmount}

        bind -N "Split window horizontally" | split-window -h
        bind -N "Split window vertically" - split-window -v

        set -s set-clipboard off
        bind P paste-buffer
        bind-key -T copy-mode-vi v send-keys -X begin-selection
        bind-key -T copy-mode-vi V send-keys -X rectangle-toggle
        unbind -T copy-mode-vi Enter
        bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel 'wl-copy'
        bind-key -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel 'wl-copy'
        bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel 'wl-copy'
      '';
    };
  };
}
