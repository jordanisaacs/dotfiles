{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.applications.neovim;
in
{
  options.jd.applications.neovim = {
    enable = mkEnableOption "neovim-flake";
  };

  config = mkIf cfg.enable {
    home = {
      packages = [ pkgs.neovimJD ];

      sessionVariables = {
        EDITOR = "vim";
      };
    };

    # TODO: Create a function for generating these better
    xdg.mimeApps.defaultApplications = {
      "application/x-shellscript" = "nvim.desktop";
      "application/x-perl" = "nvim.desktop";
      "application/json" = "nvim.desktop";
      "text/x-readme" = "nvim.desktop";
      "text/plain" = "nvim.desktop";
      "text/markdown" = "nvim.desktop";
      "text/x-csrc" = "nvim.desktop";
      "text/x-chdr" = "nvim.desktop";
      "text/x-python" = "nvim.desktop";
      "text/x-makefile" = "nvim.desktop";
      "text/x-markdown" = "nvim.desktop";
    };
  };
}
