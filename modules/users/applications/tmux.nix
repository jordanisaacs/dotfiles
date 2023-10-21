{ pkgs
, config
, lib
, ...
}:
with lib;
with builtins; let
  cfg = config.jd.applications.tmux;
in
{
  options.jd.applications.tmux.enable = mkEnableOption "tmux";

  config = mkIf cfg.enable {
    programs.tmux = {
      enable = true;
      keyMode = "vi";
      mouse = false;
      terminal = "screen-256color";
      customPaneNavigationAndResize = true;
      secureSocket = true;
      extraConfig = ''
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
