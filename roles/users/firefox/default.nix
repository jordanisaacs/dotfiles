{ pkgs, config, lib, ... }:
{
  programs.firefox = {
    enable = true;
    extensions = with pkgs.nur.repos.rycee.firefox-addons; [
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
      home = {
        id = 0;
        settings = {};
      };
    };
  };
}
