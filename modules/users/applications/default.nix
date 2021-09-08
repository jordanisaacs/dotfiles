{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.applications;
in {
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
      MOZ_USE_XINPUT2 = 1;
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

      # File manager
      nnn

      # Messaging
      slack

      # Video conference
      zoom-us

      # Productivity Suite
      libreoffice

      # Font
      (nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
    ];

    fonts.fontconfig.enable = true;

    programs.firefox = {
      enable = true;
      extensions = with pkgs.nur.repos.rycee.firefox-addons; [
        # bypass-paywalls third party
        (buildFirefoxXpiAddon {
            pname = "bypass-paywalls-firefox";
            addonId = "bypasspaywalls@bypasspaywalls";
            version = "1.7.9";
            url = "https://github.com/iamadamdev/bypass-paywalls-chrome/releases/latest/download/bypass-paywalls-firefox.xpi";
            sha256 = "Nk9ZKUPPSV+EFG9iO6W7Dv/iLX2c3Bh2GxV5nMTQ6q8=";
            
            meta = with lib; {
              description = "Bypass paywalls for a variety of news sites";
              license = pkgs.lib.licenses.mit;
              platforms = pkgs.lib.platforms.all;
            };
        })
        privacy-badger
        bitwarden
        tree-style-tab
        ublock-origin
        sponsorblock
        multi-account-containers
        clearurls
        cookie-autodelete
      ];
      profiles = {
        personal = {
          id = 0;
          settings = {};
        };
      };
    };
  };
}
