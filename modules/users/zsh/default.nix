{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.zsh;
in {
  options.jd.zsh = {
    enable = mkOption {
      description = "Enable zsh with settings";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (cfg.enable) {
    programs.zsh = {
      enable = true;
      enableAutosuggestions = true;
      enableCompletion = true;
      completionInit = ''
        autoload -U compinit
        zstyle ":completion" menu select
        zmodload zsh/complist
        compinit
        _comp_options+=(globdots) # enable hidden files
      '';
      enableSyntaxHighlighting = true;
      autocd = true;
      dotDir = ".config/zsh";
      history = {
        extended = true;
        ignoreDups = true;
        ignoreSpace = true;
        save = 10000;
        size = 10000;
        share = true;
        path = ".config/zsh/zsh_history";
      };
      initExtraFirst = ""; # add commands to top of .zshrc
      initExtraBeforeCompInit = ''
        # vi mode
        bindkey -v
        export KEYTIMEOUT=1

        # Edit line in vim with ctrl-e:
        autoload edit-command-line; zle -N edit-command-line
        bindkey '^e' edit-command-line

        # Use vim keys in tab complete menu
        bindkey -M menuselect 'h' vi-backward-char
        bindkey -M menuselect 'k' vi-up-line-or-history
        bindkey -M menuselect 'l' vi-forward-char
        bindkey -M menuselect 'j' vi-down-line-or-history
        bindkey -v '^?' backward-delete-char
      ''; # add to .zshrc before compinit
      initExtra = ''
      ''; # addd to .zshrc
      profileExtra = ""; # profiles to add to .zprofile
    };
  };
}
