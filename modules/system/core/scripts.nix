{ pkgs, ... }:
let
  runtimeShell = pkgs.runtimeShell;
in {
  sysTool = pkgs.writeScriptBin "sys" ''
    #!${runtimeShell}
    if [ -n "$INNIXSHELLHOME" ]; then
      echo "You are in a nix shell that redirected home!"
      echo "SYS will not work from here properly."
      exit 1
    fi

    case $1 in
      "clean")
        echo "Running garbage collection"
        nix-store --gc
        echo "Deduplication running... may take a while"
        nix-store --optimise
      ;;

      "update")
        echo "Updating nixos flake..."
        pushd ~/.dotfiles
        nix flake update
        popd
      ;;

      "update-index")
        echo "Updating index... may take a while"
        nix-index
      ;;

      "save")
        echo "Saving changes"
        pushd ~/.dotfiles
        git diff
        git add .
        git commit
        git pull --rebase
        git push
      ;;

      "find")
        if [ $2 = "--overlay" ]; then
          pushd ~/.dotfiles
          nix search .# $3
          popd
        else
          nix search nixpkgs $2
        fi
      ;;

      "find-doc")
        ${pkgs.manix}/bin/manix $2
      ;;

      "find-cmd")
        nix-locate --whole-name --type x --type s --no-group --type x --type s --top-level --at-root "/bin/$2"
      ;;

      "apply")
        pushd ~/.dotfiles
        if [ -z "$2" ]; then
          sudo nixos-rebuild switch --flake '.#'
        elif [ $2 = "--boot" ]; then
          sudo nixos-rebuild boot --flake '.#'
        elif [ $2 = "--test" ]; then
          sudo nixos-rebuild test --flake '.#'
        elif [ $2 = "--check" ]; then
          nixos-rebuild dry-activate --flake '.#'
        else
          echo "Unknown option $2"
        fi
        popd
      ;;

      "apply-user")
        pushd ~/.dotfiles

        #--impure is required so package can reach out to /etc/hmsystemdata.json
        nix build --impure .#homeManagerConfigurations.$USER.activationPackage
        ./result/activate
        popd
      ;;

      "installed")
        nix-store -q -R /run/current-system | sed -n -e 's/\nix\/store\/[0-9a-z]\{32\}-//p' | sort | uniq
      ;;

      "which")
        nix-store -qR $(which $2)
      ;;

      "exec")
        shift 1
        cmd=$1
        pkgs=$(nix-locate --minimal --no-group --type x --type s --top-level --whole-name --at-root "/bin/$cmd")
        count=$(echo -n "$pkgs" | grep -c "^")

        case $count in
          0)
            >&2 echo "$1: not found!"
            exit 2
          ;;

          1)
            nix-build --no-out-link -A $pkgs "<nixpkgs>"
            if [ "$?" -eq 0 ]; then
              nix-shell -p $pkgs --run "$(echo $@)"
              exit $?
            fi
          ;;

          *)
            PS3="Please select package to run command from:"
            select p in $pkgs
            do
              nix-build --no-out-link -A $p "<nixpkgs>"
              if [ "$?" -eq 0 ]; then
                nix-shell -p $pkgs --run "$(echo $@)"
                exit $?
              fi

              >&2 echo "Unable to run command"
              exit $?
            done
          ;;
        esac
      ;;

      *)
        echo "Usage:"
        echo "sys command"
        echo ""
        echo "Commands:"
        echo "clean - Garbage collect and hard link nix store"
        echo "update - Updates dotfiles flake."
        echo "update-index - Updates index of nixpkgs. Used for exec"
        echo "find [--overlay] - Find a nix package (overlay for custom packages)"
        echo "find-doc - Finds documentation on a config item"
        echo "find-cmd - Finds the package a command is in"
        echo "apply - Applies current system configuration in dotfiles."
        echo "apply-user - Applies current home manager configuration in dotfiles."
        echo "shell - Runs a shell defined in flake."
        echo "installed - Lists all installed packages."
        echo "which - Prints the closure of target file"
        echo "exec - executes a command"
      ;;
    esac
  '';
}
