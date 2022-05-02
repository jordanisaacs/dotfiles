{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.zsh;
in {
  # Interesting configs:
  # https://vermaden.wordpress.com/2021/09/19/ghost-in-the-shell-part-7-zsh-setup/

  options.jd.zsh = {
    enable = mkOption {
      description = "Enable zsh with settings";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (cfg.enable) (
    let
      # Remove home directory from xdg
      dotDir = builtins.substring ((builtins.stringLength config.home.homeDirectory) + 1) (builtins.stringLength config.xdg.configHome) config.xdg.configHome;
    in {
      home.file."${config.xdg.configHome}/zsh/.p10k.zsh" = {
        source = ./p10k.zsh;
      };

      programs.zsh = {
        enable = true;
        enableAutosuggestions = true;
        enableSyntaxHighlighting = true;
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

          # Use vim keys in tab complete menu
          bindkey -M menuselect 'h' vi-backward-char
          bindkey -M menuselect 'k' vi-up-line-or-history
          bindkey -M menuselect 'l' vi-forward-char
          bindkey -M menuselect 'j' vi-down-line-or-history
          bindkey -v '^?' backward-delete-char
        '';
        autocd = true;
        dotDir = "${dotDir}/zsh";
        history = {
          extended = true;
          ignoreDups = true;
          ignoreSpace = true;
          save = 10000;
          size = 10000;
          share = true;
          path = "${config.xdg.dataHome}/zsh/zsh_history";
        };
        initExtraFirst = ""; # add commands to top of .zshrc
        initExtraBeforeCompInit = ''
        ''; # add to .zshrc before compinit
        initExtra = ''

          # Edit line in vim with ctrl-e:
          autoload edit-command-line; zle -N edit-command-line
          bindkey '^e' edit-command-line

          # https://unix.stackexchange.com/questions/433273/changing-cursor-style-based-on-mode-in-both-zsh-and-vim
          # vi mode
          bindkey -v
          export KEYTIMEOUT=1

          function zle-keymap-select {
            if [[ ''${KEYMAP} == vicmd ]] ||
               [[ $1 = 'block' ]]; then
              echo -ne '\e[2 q'
            elif [[ ''${KEYMAP} == main ]] ||
                 [[ ''${KEYMAP} == viins ]] ||
                 [[ ''${KEYMAP} = "" ]] ||
                 [[ $1 = 'beam' ]]; then
              echo -ne '\e[5 q'
            fi
          }
          zle -N zle-keymap-select
          zle-line-init() {
            zle -K viins
            echo -ne '\e[6 q'
          }
          zle -N zle-line-init
          echo -ne '\e[6 q' # use beam shape cursor on startup
          preexec() { echo -ne '\e[6 q' ;} # use beam shape cursor for each new prompt

          # Source powerlevel10k
          source ${config.xdg.configHome}/zsh/.p10k.zsh
          ${
            ""
            # Source zsh-vi-mode
            # source ${pkgs.myPkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.zsh
          }
          source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme

          # Disable less(1) history
          export LESSHISTSIZE=0
        ''; # addd to .zshrc
        profileExtra = ""; # profiles to add to .zprofile
      };
    }
  );
}
