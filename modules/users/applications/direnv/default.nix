{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.applications.direnv;
in {
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
      '';
    };
  };
}
