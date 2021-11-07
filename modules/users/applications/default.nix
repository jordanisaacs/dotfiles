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
      weechat

      # Video conference
      zoom-us

      # Productivity Suite
      libreoffice
      pdftk

      # Video
      youtube-dl

      # Font
      (nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
    ];

    fonts.fontconfig.enable = true;

    programs.mpv = {
      enable = true;
      config = {
        profile = "gpu-hq";
        vo = "gpu";
        hwdec = "auto-safe";
        ytdl-format = "ytdl-format=bestvideo[height<=?1920][fps<=?30][vcodec!=?vp9]+bestaudio/best";
      };
    };

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
        (buildFirefoxXpiAddon {
          pname = "cookie-quick-manager";
          addonId = "{60f82f00-9ad5-4de5-b31c-b16a47c51558}";
          version = "0.5rc2";
          url = "https://addons.mozilla.org/firefox/downloads/file/3343599/cookie_quick_manager-0.5rc2-an+fx.xpi";
          sha256 = "uCbkQ0OMiAs5mOQuCZ0OGUn/UUiceItQGTuS74BCbG4=";

          meta = with lib; {
            description = "Manage cookies better";
            license = licenses.gpl3;
            platforms = platforms.all;
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
          settings =
            let
              frameworkHardwareAccel = { };
              #frameworkHardwareAccel = if config.machineData.name == "framework" then {
              #  "media.ffmpeg.vaapi.enabled" = true;
              #  "media.ffvpx.enabled" = false;
              #  "media.navigator.mediadatadecoder_vpx_enabled" = true;
              #  "media.rdd-process.enabled" = false;
              #  "media-ffvpx.enabled" = false;
              #  "gfx.webrender.all" = true;
              #  "gfx.webrender.enabled" = true;
              #} else {};

              newTab =
                let
                  newTabPage = "browser.newtabpage";
                  activityStream = "${newTabPage}.activity-stream";
                in
                {
                  "${activityStream}.feeds.section.highlights" = true;
                  "${activityStream}.feeds.section.topstories" = false;
                  "${activityStream}.feeds.section.highlights.includePocket" = false;
                  "${activityStream}.section.highlights.includePocket" = false;
                  "${activityStream}.feeds.topsites" = true;
                  "${activityStream}.showSearch" = false;
                };

              uiState = {
                "browser.uiCustomization.state" = ''{"placements":{"widget-overflow-fixed-list":[],"nav-bar":["back-button","forward-button","stop-reload-button","customizableui-special-spring1","urlbar-container","customizableui-special-spring2","downloads-button","fxa-toolbar-menu-button","_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action","bypasspaywalls_bypasspaywalls-browser-action","_74145f27-f039-47ce-a470-a662b129930a_-browser-action","cookieautodelete_kennydo_com-browser-action","_testpilot-containers-browser-action","ublock0_raymondhill_net-browser-action","_a6c4a591-f1b2-4f03-b3ff-767e5bedf4e7_-browser-action"],"toolbar-menubar":["menubar-items"],"TabsToolbar":["tabbrowser-tabs","new-tab-button","alltabs-button"],"PersonalToolbar":["import-button","personal-bookmarks"]},"seen":["save-to-pocket-button","developer-button","_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action","bypasspaywalls_bypasspaywalls-browser-action","_74145f27-f039-47ce-a470-a662b129930a_-browser-action","cookieautodelete_kennydo_com-browser-action","_testpilot-containers-browser-action","ublock0_raymondhill_net-browser-action","_a6c4a591-f1b2-4f03-b3ff-767e5bedf4e7_-browser-action"],"dirtyAreaCache":["nav-bar","PersonalToolbar","toolbar-menubar","TabsToolbar"],"currentVersion":17,"newElementCount":2}'';
              };

              searchBar = {
                "browser.urlbar.suggest.quicksuggest.sponsored" = false;
              };

              telemetry = {
                "browser.newtabpage.activity-stream.telemetry" = false;
                "browser.newtabpage.activity-stream.feeds.telemetry" = false;
                "browser.ping-centre.telemetry" = false;
                "toolkit.telemetry.reportingpolicy.firstRun" = false;
                "toolkit.telemetry.unified" = false;
                "toolkit.telemetry.archive.enabled" = false;
                "toolkit.telemetry.updatePing.enabled" = false;
                "toolkit.telemetry.shutdownPingSender.enabled" = false;
                "toolkit.telemetry.newProfilePing.enabled" = false;
                "toolkit.telemetry.bhrPing.enabled" = false;
                "toolkit.telemetry.firstShutdownPing.enabled" = false;
                "datareporting.healthreport.uploadEnabled" = false;
                "datareporting.policy.dataSubmissionEnabled" = false;
                "app.shield.optoutstudies.enable" = false;
              };

              privacy = {
                "dom.event.clipboardevents.enabled" = false;
                "dom.battery.enabled" = false;
              };

              https = {
                "dom.security.https_only_mode" = true;
                "dom.security.https_only_mode_ever_enabled" = true;
              };
            in
            https // uiState // newTab // frameworkHardwareAccel // privacy // telemetry // searchBar;
        };
      };
    };
  };
}
