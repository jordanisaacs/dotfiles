{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.applications;
in
{
  options.jd.applications = {
    enable = mkOption {
      description = "Enable a set of common applications";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (cfg.enable) {
    home.sessionVariables = {
      EDITOR = "vim";
    };

    home.packages = with pkgs; [
      # Password manager
      bitwarden

      # Note taking
      obsidian #knowledge base
      xournalpp #drawing

      # Text editor
      neovimJD

      # ssh mount
      sshfs

      # CLI apps
      nnn # file manager
      grit # to-do
      timewarrior

      # Messaging
      slack

      # Video conference
      zoom-us

      # Productivity Suite
      pdftk

      # Video
      youtube-dl

      # Bookmarks
      buku

      # Font
      (nerdfonts.override { fonts = [ "JetBrainsMono" ]; })

      # Typing fonts
      carlito

      # Calculator
      bc
      bitwise
    ];

    fonts.fontconfig.enable = true;

    programs.taskwarrior = {
      enable = true;
    };

    # Taskwarrior + timewarrior integration: https://timewarrior.net/docs/taskwarrior/
    home.activation = {
      tasktime = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p ${config.xdg.dataHome}/task/hooks/
        $DRY_RUN_CMD rm -rf ${config.xdg.dataHome}/task/hooks/on-modify.timewarrior
        $DRY_RUN_CMD cp ${pkgs.timewarrior}/share/doc/timew/ext/on-modify.timewarrior ${config.xdg.dataHome}/task/hooks/
        PYTHON3="#!${pkgs.python3}/bin/python3"
        $DRY_RUN_CMD ${pkgs.gnused}/bin/sed -i "1s@.*@$PYTHON3@" ${config.xdg.dataHome}/task/hooks/on-modify.timewarrior
        $DRY_RUN_CMD chmod +x ${config.xdg.dataHome}/task/hooks/on-modify.timewarrior
      '';
    };

    programs.mpv = {
      enable = true;
      config = {
        profile = "gpu-hq";
        vo = "gpu";
        hwdec = "auto-safe";
        ytdl-format = "ytdl-format=bestvideo[height<=?1920][fps<=?30][vcodec!=?vp9]+bestaudio/best";
      };
    };

  };
}
