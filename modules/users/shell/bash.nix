{ pkgs
, config
, lib
, ...
}:
with lib; let cfg = config.jd;
in
{
  config = mkIf (cfg.shell == "bash") {
    # some nice info on readline: https://twobithistory.org/2019/08/22/readline.html
    programs.readline = {
      enable = true;
      includeSystemConfig = true;
      variables = {
        "keyseq-timeout" = 250;
        "editing-mode" = "vi";

        # display all possible matches for an ambiguous pattern at first tab
        "show-all-if-ambiguous" = true;

        # append char to indicate type
        "visible-stats" = true;
        # color files by types
        "colored-stats" = true;
        "mark-symlinked-directories" = true;
        "colored-completion-prefix" = true;
        "menu-complete-display-prefix" = true;
      };

      extraConfig =
        # tab through autocomplete
        ''
          tab: menu-complete
          "\e[Z": menu-complete-backward
        ''
        +
        # https://wiki.archlinux.org/title/readline#Different_cursor_shapes_for_each_mode
        ''
          set show-mode-in-prompt on
          $if term=linux
          	set vi-ins-mode-string \1\e[?0c\2
          	set vi-cmd-mode-string \1\e[?8c\2
          $else
          	set vi-ins-mode-string \1\e[6 q\2
          	set vi-cmd-mode-string \1\e[2 q\2
          $endif
        ''
        # from http://www.usenix.org.uk/content/bash.html#input
        + ''
          $if mode=vi

          set keymap vi-command
          Control-l: clear-screen
          "\C-o": operate-and-get-next

          "#": insert-comment
          ".": "i !*\r"
          "|": "A | "
          "D": kill-line
          "C": "Da"
          "dw": kill-word
          "dd": kill-whole-line
          "db": backward-kill-word
          "cc": "ddi"
          "cw": "dwi"
          "cb": "dbi"
          "daw": "lbdW"
          "yaw": "lbyW"
          "caw": "lbcW"
          "diw": "lbdw"
          "yiw": "lbyw"
          "ciw": "lbcw"
          "da\"": "lF\"df\""
          "di\"": "lF\"lmtf\"d`t"
          "ci\"": "di\"i"
          "ca\"": "da\"i"
          "da'": "lF'df'"
          "di'": "lF'lmtf'd`t"
          "ci'": "di'i"
          "ca'": "da'i"
          "da`": "lF\`df\`"
          "di`": "lF\`lmtf\`d`t"
          "ci`": "di`i"
          "ca`": "da`i"
          "da(": "lF(df)"
          "di(": "lF(lmtf)d`t"
          "ci(": "di(i"
          "ca(": "da(i"
          "da)": "lF(df)"
          "di)": "lF(lmtf)d`t"
          "ci)": "di(i"
          "ca)": "da(i"
          "da{": "lF{df}"
          "di{": "lF{lmtf}d`t"
          "ci{": "di{i"
          "ca{": "da{i"
          "da}": "lF{df}"
          "di}": "lF{lmtf}d`t"
          "ci}": "di}i"
          "ca}": "da}i"
          "da[": "lF[df]"
          "di[": "lF[lmtf]d`t"
          "ci[": "di[i"
          "ca[": "da[i"
          "da]": "lF[df]"
          "di]": "lF[lmtf]d`t"
          "ci]": "di]i"
          "ca]": "da]i"
          "da<": "lF<df>"
          "di<": "lF<lmtf>d`t"
          "ci<": "di<i"
          "ca<": "da<i"
          "da>": "lF<df>"
          "di>": "lF<lmtf>d`t"
          "ci>": "di>i"
          "ca>": "da>i"
          "da/": "lF/df/"
          "di/": "lF/lmtf/d`t"
          "ci/": "di/i"
          "ca/": "da/i"
          "da:": "lF:df:"
          "di:": "lF:lmtf:d`t"
          "ci:": "di:i"
          "ca:": "da:i"
          "gg": beginning-of-history
          "G": end-of-history
          ?: reverse-search-history
          /: forward-search-history

          set keymap vi-insert
          "\C-o": operate-and-get-next
          "\C-l": clear-screen
          "\C-a": beginning-of-line
          "\C-e": end-of-line
          "\e[A": history-search-backward
          "\e[B": history-search-forward
          $endif
        '';
    };

    programs.bash = {
      enable = true;
      historySize = 100;
      historyFileSize = 10000;
      historyControl = [ "ignorespace" "ignoredups" ];
      enableCompletion = true;
      bashrcExtra = ''
        PROMPT_COMMAND=__prompt_command

        __GREEN="\[$(tput setaf 2)\]"
        __RED="\[$(tput setaf 1)\]"
        __BLUE="\[$(tput setaf 6)\]"
        __ORANGE="\[$(tput setaf 215)\]"
        __GRAY="\[$(tput setaf 145)\]"
        __RESET="\[$(tput sgr0)\]"
        __BOLD="\[$(tput bold)\]"
        __ITALIC="\[$(tput sitm)\]"

        source ${pkgs.git}/share/git/contrib/completion/git-prompt.sh
        # kinda slow :(
        # source ${pkgs.nix-index}/etc/profile.d/command-not-found.sh

        __prompt_command() {
          es=$?

          history -a

          PS1=
          if [ -n "$IN_NIX_SHELL" ]; then
            PS1+="''${__GRAY}(nix-shell) "
          fi

          PS1+="''${__RESET}''${__BLUE}''${__ITALIC}\w "

          PS1+="''${__RESET}''${__ORANGE}$(__git_ps1 '(%s) ')"

          PS1+="''${__RESET}''${__BOLD}"
          if [ $es -eq 0 ]
          then
              PS1+="''${__GREEN}> "
          else
              PS1+="''${__RED}> "
          fi

          PS1+="''${__RESET}"
        }
      '';
    };
  }
  ;
}
