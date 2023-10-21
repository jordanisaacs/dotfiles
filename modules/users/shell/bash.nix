{ pkgs
, config
, lib
, ...
}:
with lib; let cfg = config.jd;
in
{
  config = mkIf (cfg.shell == "bash") {
    jd.applications.readline.enable = true;

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
