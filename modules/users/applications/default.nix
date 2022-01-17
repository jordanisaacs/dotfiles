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

      # Messaging
      slack
      discord
      weechat

      # Video conference
      zoom-us

      # Productivity Suite
      libreoffice
      pdftk

      # Video
      youtube-dl

      # Bookmarks
      buku

      # Font
      (nerdfonts.override { fonts = [ "JetBrainsMono" ]; })

      # Typing fonts
      carlito
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
        (buildFirefoxXpiAddon {
          pname = "pinboard-extension";
          addonId = "pinboardff@pinboard.in";
          version = "1.1.0";
          url = "https://addons.mozilla.org/firefox/downloads/file/3722104/pinboard_extension-1.1.0-fx.xpi";
          sha256 = "sha256-40bE1GJgoOn7HbO85XCzzfLeVWwuitXBXmWKTkrWGII=";

          meta = with lib; {
            description = "Quick pinboard adder";
            platforms = pkgs.lib.platforms.all;
          };
        })
        (buildFirefoxXpiAddon {
          pname = "redirector";
          addonId = "redirector@einaregilsson.com";
          version = "3.5.3";
          url = "https://addons.mozilla.org/firefox/downloads/file/3535009/redirector-3.5.3-an+fx.xpi";
          sha256 = "sha256-7dvT1ZROdI0L1uy22enPDgwC3O1vQtshqrZBkOccD3E=";

          meta = with lib; {
            description = "Redirect links";
            platforms = pkgs.lib.platforms.all;
          };
        })
        (buildFirefoxXpiAddon {
          pname = "rust-search-extension";
          addonId = "rust-search-extension@huhu.io";
          version = "3.5.3";
          url = "https://addons.mozilla.org/firefox/downloads/file/3859949/rust_search_extension-1.4.0-fx.xpi";
          sha256 = "sha256-7uCF49A+HePZ0/yv0eOwqK8ENd6N1t4LMMvLq9fxEAA=";

          meta = with lib; {
            description = "Rust search extension";
            platforms = pkgs.lib.platforms.all;
          };
        })
        bitwarden
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

              graphics = {
                "media.ffmpeg.vaapi.enabled" = true;
                "media.rdd-ffmpeg.enabled" = true;
                "media.navigator.medidataencoder_vpx_enabled" = true;
              };
            in
            https // uiState // newTab // frameworkHardwareAccel // privacy // telemetry // searchBar // graphics;
        };
      };
    };
  };
}
