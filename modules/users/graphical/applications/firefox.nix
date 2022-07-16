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
  options.jd.graphical.applications.firefox = {
    enable = mkOption {
      type = types.bool;
      description = "Enable firefox with config [firefox]";
    };
  };

  config = mkIf (isGraphical && cfg.enable && cfg.firefox.enable) {
    programs.firefox = {
      enable = true;
      extensions = with pkgs.nur.repos.rycee.firefox-addons; [
        (buildFirefoxXpiAddon {
          pname = "arc-dark-theme-firefox";
          addonId = "arc-dark-theme@afnankhan";
          version = "2021.6.2";
          url = "https://addons.mozilla.org/firefox/downloads/file/3786185/arc_dark_theme-2021.6.2-an+fx.xpi";
          sha256 = "TRXQCboplZmxi3/HzU5HYs1xEIO0RRzCClliEu6MEEM=";

          meta = with lib; {
            description = "Arc dark theme";
            license = pkgs.lib.licenses.cc-by-30;
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
        user-agent-string-switcher
        bypass-paywalls-clean
        redirector
        rust-search-extension
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
          settings = let
            newTab = let
              activityStream = "browser.newtabpage.activity-stream";
            in {
              "${activityStream}.feeds.topsites" = true;
              "${activityStream}.feeds.section.highlights" = true;
              "${activityStream}.feeds.section.topstories" = false;
              "${activityStream}.feeds.section.highlights.includePocket" = false;
              "${activityStream}.section.highlights.includePocket" = false;
              "${activityStream}.showSearch" = false;
              "${activityStream}.showSponsoredTopSites" = false;
              "${activityStream}.showSponsorsed" = false;
            };

            searchBar = {
              "browser.urlbar.suggest.quicksuggest.sponsored" = false;
              "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
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

            domPrivacy = {
              # clipboard events: https://superuser.com/questions/1595994/dont-let-websites-overwrite-clipboard-in-firefox-without-explicitly-giving-perm
              # Breaks copy/paste on websites
              #"dom.event.clipboardevents.enabled" = false;
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

            general_settings = {
              "widget.use-xdg-desktop-portal.file-picker" = 2;
              "widget.use-xdg-desktop-portal.mime-handler" = 2;
              "browser.aboutConfig.showWarning" = false;
              "browser.shell.checkDefaultBrowser" = false;
              "browser.toolbars.bookmarks.visibility" = "newtab";
              "browser.urlbar.showSearchSuggestionsFirst" = false;
              "extensions.htmlaboutaddons.inline-options.enabled" = false;
              "extensions.htmlaboutaddons.recommendations.enabled" = false;
              "extensions.pocket.enabled" = false;
              "browser.fullscreen.autohide" = false;
            };

            passwords = {
              "signon.rememberSignons" = false;
              "signon.autofillForms" = false;
              "signon.generation.enabled" = false;
              "signon.management.page.breach-alerts.enabled" = false;
            };

            downloads = {
              "browser.download.useDownloadDir" = false;
            };
          in
            general_settings // https // newTab // searchBar // domPrivacy // telemetry // graphics // downloads;
        };
      };
    };
  };
}
