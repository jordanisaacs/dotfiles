{ pkgs
, config
, lib
, ...
}:
with lib;
with builtins; let
  cfg = config.jd.applications;
in
{
  imports = [
    ./taskwarrior.nix
    ./direnv.nix
    ./bat.nix
    ./tldr.nix
    ./syncthing.nix
    ./neovim.nix
    ./neomutt.nix
    ./readline.nix
    ./lnav.nix
    ./tmux.nix
    ./podman.nix
  ];

  options.jd.applications = {
    enable = mkEnableOption "a set of common non-graphical applications";
  };

  config = mkIf cfg.enable {
    # TTY compatible CLI applications
    home.packages = with pkgs; [
      # ssh mount
      sshfs

      # CLI tools
      glow
      nnn # file manager
      grit # to-do
      buku # bookmarks
      yt-dlp # download youtube
      pdftk # pdf editing
      graphviz # dot

      # Spell checking
      # Setting up dictionary modified from:
      # https://www.thedroneely.com/posts/nixos-in-the-wild/#libreoffice-and-spell-checking
      # https://github.com/NixOS/nixpkgs/issues/14430
      # https://github.com/NixOS/nixpkgs/blob/nixos-22.11/pkgs/development/libraries/hunspell/0001-Make-hunspell-look-in-XDG_DATA_DIRS-for-dictionaries.patch
      hunspell
      hunspellDicts.en_US-large
      hyphen

      # nixpkgs
      nixpkgs-review

      # terminal session recorder
      asciinema

      # terminal art
      pipes-rs
      cbonsai

      # Themes
      theme-sh

      # music
      playerctl

      # A basic python environment
      (python3.withPackages (ps: with ps; [ pandas requests ]))
    ];

    services.playerctld.enable = true;

    systemd.user.timers."nix-index" = {
      Unit = {
        Description = "Run nix-index weekly";
      };
      Timer = {
        OnCalendar = "weekly";
        Persistent = true;
      };
    };
    systemd.user.services."nix-index" = {
      Unit = {
        Description = "Update nix-index";
      };
      Service = {
        ExecStart = "${pkgs.nix-index}/bin/nix-index";
        Type = "oneshot";
        Restart = "on-abort";
      };
    };
  };
}
