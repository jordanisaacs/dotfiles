{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd;
  vim = config.jd.keybindings == "vim";
in
{
  # Interesting configs:
  # https://vermaden.wordpress.com/2021/09/19/ghost-in-the-shell-part-7-zsh-setup/
  config = mkIf (cfg.shell == "zsh") {
    xdg.configFile."zsh/.p10k.zsh" = {
      source = ./p10k.zsh;
    };

    programs.zsh = {
      enable = true;
      autosuggestion.enable = true;
      defaultKeymap = if vim then "viins" else "emacs";
      historySubstringSearch.enable = true;
      syntaxHighlighting.enable = true;
      enableCompletion = true;
      completionInit = ''
        autoload -U compinit
        # https://unix.stackexchange.com/questions/214657/what-does-zstyle-do
        zstyle ":completion:*" menu select
        # case insensitive
        zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
        zmodload zsh/complist
        compinit
        _comp_options+=(globdots) # enable hidden files

      ''
      + (
        if vim then
          ''
            bindkey -M menuselect 'h' vi-backward-char
            bindkey -M menuselect 'k' vi-up-line-or-history
            bindkey -M menuselect 'l' vi-forward-char
            bindkey -M menuselect 'j' vi-down-line-or-history
            bindkey -M viins '^?' backward-delete-char
          ''
        else
          ''
            bindkey -M menuselect '^b' backward-char
            bindkey -M menuselect '^p' up-line-or-history
            bindkey -M menuselect '^f' forward-char
            bindkey -M menuselect '^n' down-line-or-history
          ''
      );
      autocd = true;
      dotDir = "${config.xdg.configHome}/zsh";
      history = {
        extended = true;
        ignoreDups = true;
        ignoreSpace = true;
        save = 10000;
        size = 10000;
        share = true;
        path = "${config.xdg.dataHome}/zsh/zsh_history";
      };
      # Ghostty supplies prompt, working-directory and cursor integration.
      initContent =
        (optionalString vim ''
          autoload edit-command-line
          zle -N edit-command-line
          bindkey -M viins '^e' edit-command-line
          KEYTIMEOUT=1
        '')
        + ''
          # Source powerlevel10k
          source ${config.xdg.configHome}/zsh/.p10k.zsh
          source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme

          # Disable less(1) history
          export LESSHISTSIZE=0
        ''; # addd to .zshrc
      profileExtra = ""; # profiles to add to .zprofile
    };
  };
}
