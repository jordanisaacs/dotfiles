{ pkgs, config, lib, ... }:
with lib;
let cfg = config.jd.applications.readline;
in {
  options.jd.applications.readline.enable = mkEnableOption "readline";

  config = mkIf cfg.enable {
    # some nice info on readline: https://twobithistory.org/2019/08/22/readline.html
    programs.readline = {
      enable = true;
      includeSystemConfig = true;
      variables = {
        "keyseq-timeout" = 250;
        "editing-mode" = "emacs";
        "bell-style" = "none";

        # display all possible matches for an ambiguous pattern at first tab
        "show-all-if-ambiguous" = true;
        "show-all-if-unmodified" = true;

        # don't duplicate single match insert
        "skip-completed-text" = true;

        # append char to indicate type
        "visible-stats" = true;
        # marking files
        "mark-directories" = true;
        "mark-modified-lines" = true;
        "mark-symlinked-directories" = true;
        "menu-complete-display-prefix" = true;

        # color files by types
        "colored-stats" = true;
        "colored-completion-prefix" = true;
      };

      extraConfig =
        # tab through autocomplete
        ''
          tab: menu-complete
          "\e[Z": menu-complete-backward
        '' +
        # https://wiki.archlinux.org/title/readline#Different_cursor_shapes_for_each_mode
        ''
          $if lnav
          	set vi-ins-mode-string "I"
          	set vi-cmd-mode-string "N"
          $else
          $if term=linux
          	set vi-ins-mode-string \1\e[?0c\2
          	set vi-cmd-mode-string \1\e[?8c\2
          $else
          	set vi-ins-mode-string \1\e[6 q\2
          	set vi-cmd-mode-string \1\e[2 q\2
          $endif
          $endif
        ''
        # emacs mode
        + ''
          $if mode=emacs
          "\C-u": universal-argument
          "\C-x\C-r": re-read-init-file
          $endif
        ''
        # VI mode from http://www.usenix.org.uk/content/bash.html#input
        + ''
          $if mode=vi
          set show-mode-in-prompt on

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
  };
}
