{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.applications.direnv;
in
{
  options.jd.applications.direnv = {
    enable = mkOption {
      description = "Enable direnv";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (config.jd.applications.enable && cfg.enable) {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
      # https://github.com/nix-community/nix-direnv#storing-direnv-outside-the-project-directory
      stdlib = ''
        declare -A direnv_layout_dirs
        direnv_layout_dir() {
          echo "''${direnv_layout_dirs[$PWD]:=$(
            echo -n ${config.xdg.cacheHome}/direnv/layouts/
            echo -n "$PWD" | ${pkgs.perl}/bin/shasum | cut -d ' ' -f 1
          )}"
        }

        export IS_DIRENV=1

        export_alias() {
          local name=$1
          shift
          local alias_dir=${config.xdg.cacheHome}/direnv/aliases
          local target="$alias_dir/$name"
          local oldpath="$PATH"
          mkdir -p "$alias_dir"
          if ! [[ ":$PATH:" == *":$alias_dir:"* ]]; then
            PATH_add "$alias_dir"
          fi

          echo "#!/usr/bin/env bash" > "$target"
          echo "PATH=$oldpath" >> "$target"
          echo "$@" >> "$target"
          chmod +x "$target"
        }
      '';
    };
  };
}
