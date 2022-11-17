{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.graphical.applications;
  isGraphical = let
    cfg = config.jd.graphical;
  in (cfg.xorg.enable == true || cfg.wayland.enable == true);
in {
  options.jd.graphical.applications.libreoffice = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable libreoffice with config [libreoffice]";
    };
  };

  config = mkIf (isGraphical && cfg.enable && cfg.libreoffice.enable) {
    home.packages = with pkgs; [libreoffice-fresh];

    # Setting up dictionary modified from:
    # https://www.thedroneely.com/posts/nixos-in-the-wild/#libreoffice-and-spell-checking

    home.sessionVariables = {
      DICPATH = "${config.xdg.dataHome}/dictionary/hunspell:${config.xdg.dataHome}/dictionary/hyphen";
    };
    # $DRY_RUN_CMD unlink ${config.xdg.dataHome}/dictionary/hunspell
    # $DRY_RUN_CMD unlink ${config.xdg.dataHome}/dictionary/myspell
    # $DRY_RUN_CMD unlink ${config.xdg.dataHome}/dictionary/hyphen

    home.activation = {
      dictionaryLinker = lib.hm.dag.entryAfter ["writeBoundary"] ''
        $DRY_RUN_CMD mkdir -p ${config.xdg.dataHome}/dictionary
        $DRY_RUN_CMD ln -sfn ${pkgs.hunspellDicts.en_US-large}/share/hunspell ${config.xdg.dataHome}/dictionary/hunspell
        $DRY_RUN_CMD ln -sfn ${pkgs.hunspellDicts.en_US-large}/share/myspell ${config.xdg.dataHome}/dictionary/myspell
        $DRY_RUN_CMD ln -sfn ${pkgs.hyphen}/share/hyphen ${config.xdg.dataHome}/dictionary/hyphen
      '';
    };
  };
}
