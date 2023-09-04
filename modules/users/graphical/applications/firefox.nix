{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.graphical.applications;
in {
  options.jd.graphical.applications.firefox = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable firefox with config [firefox]";
    };
  };

  config = mkIf cfg.firefox.enable (mkMerge [
    (mkIf config.jd.impermanence.enable {
      home.persistence.${config.jd.impermanence.persistPool} = [".mozilla"];
    })
    {
      home.file.".mozilla/firefox/ignore-dev-edition-profile".text = "";

      xdg = {
        mimeApps = {
          defaultApplications = {
            "application/xhtml+xml" = "firefox.desktop";
            "application/xhtml_xml" = "firefox.desktop";
            "text/html" = "firefox.desktop";

            "x-scheme-handler/http" = "firefox.desktop";
            "x-scheme-handler/https" = "firefox.desktop";
          };
        };
      };

      programs.firefox = {
        enable = true;
        package = pkgs.wrapFirefox pkgs.firefox-devedition-unwrapped {
          extraNativeMessagingHosts = with pkgs.nur.repos.wolfangaukang; [vdhcoapp];
        };
        profiles = {
          personal = {
            id = 0;
            extensions = with pkgs.nur.repos.rycee.firefox-addons; let
              firefoxTheme =
                if (config.jd.graphical.theme == "arc-dark")
                then
                  (buildFirefoxXpiAddon {
                    pname = "arc-dark-theme-firefox";
                    addonId = "arc-dark-theme@afnankhan";
                    version = "2021.6.2";
                    url = "https://addons.mozilla.org/firefox/downloads/file/3786185/arc_dark_theme-2021.6.2-an+fx.xpi";
                    sha256 = "TRXQCboplZmxi3/HzU5HYs1xEIO0RRzCClliEu6MEEM=";

                    meta = with lib; {
                      description = "Arc dark theme";
                      license = licenses.cc-by-30;
                      platforms = platforms.all;
                    };
                  })
                else
                  (buildFirefoxXpiAddon {
                    pname = "materia-dark-gtk-theme-firefox";
                    addonId = "{6aff6b84-e31b-45c3-acfa-ef1b9351607d}";
                    version = "1.0";
                    url = "https://addons.mozilla.org/firefox/downloads/file/3860526/materia_gtk_dark-1.0.xpi";
                    sha256 = "mVcT7ssJmYjIHIgvtAkEahs5u4rsAFigYcPMaPbfhr0=";

                    meta = with lib; {
                      description = "Materia dark gtk theme";
                      license = licenses.cc-by-30;
                      platforms = platforms.all;
                    };
                  });
            in [
              firefoxTheme
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
                pname = "kagi-firefox";
                addonId = "search@kagi.com";
                version = "0.3.3";
                url = "https://addons.mozilla.org/firefox/downloads/file/4144699/kagi_search_for_firefox-0.3.3.xpi";
                sha256 = "0hcw172sj4x4kawqfcxzgzdrrcivp6v6r84vxcykxd3b4nd0b2p2";

                meta = with lib; {
                  description = ''
                    A simple helper extension for setting Kagi as a default search engine, and automatically logging in to Kagi in private browsing windows.
                  '';
                  license = licenses.mpl20;
                  platforms = platforms.all;
                };
              })
              (buildFirefoxXpiAddon {
                pname = "languagetool-firefox";
                version = "5.8.10";
                addonId = "languagetool-webextension@languagetool.org";
                url = "https://addons.mozilla.org/firefox/downloads/file/4026397/languagetool-5.8.10.xpi";
                sha256 = "sha256-3OPw5oVD5kqX9mnxVOm5pEWSKNiqJVx8whh/bEuremE=";

                meta = with lib; {
                  description = ''
                    Check your texts for spelling and grammar problems everywhere on the web
                  '';
                  platforms = platforms.all;
                };
              })
              (buildFirefoxXpiAddon {
                pname = "enforce-browser-fonts";
                version = "1.2";
                addonId = "{83e08b00-32de-44e7-97bb-1bab84d1350f}";
                url = "https://addons.mozilla.org/firefox/downloads/file/3782841/enforce_browser_fonts-1.2.xpi";
                sha256 = "sha256-h8h1hXim3d9y+Anze3ENz1dAneNXywINwcGXRieGl0U=";

                meta = with lib; {
                  description = ''
                    Enforce browser fonts easily instead of letting websites use their own fonts.
                    Easily toggle between browser fonts and website fonts by clicking on addon toolbar
                    icon or its keyboard shortcut (Alt-Comma).
                  '';
                  platforms = platforms.all;
                };
              })

              # Rycee NUR: https://nur.nix-community.org/repos/rycee/
              user-agent-string-switcher
              (bypass-paywalls-clean.override {
                addonId = "magnolia@12.34";
                url = "https://gitlab.com/magnolia1234/bpc-uploads/-/raw/master/bypass_paywalls_clean-3.2.5.0.xpi";
                sha256 = "sha256-m1BVji6Ka3+vRlfdulfN+Ffi81pSzlQObgwrSkbr0IU=";
              })
              redirector
              rust-search-extension
              bitwarden
              ublock-origin
              multi-account-containers
              clearurls
              cookie-autodelete
              firefox-translations
              video-downloadhelper

              # Youtube
              sponsorblock
              return-youtube-dislikes
            ];
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
                "${activityStream}.showSponsored" = false;
              };

              searchBar = {
                "browser.urlbar.suggest.quicksuggest.sponsored" = false;
                "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
                "browser.newtabpage.activity-stream.improvesearch.topSiteSearchShorcuts" = false;
                "browser.urlbar.showSearchSuggestionsFirst" = false;
              };

              extensions = {
                "extensions.update.autoUpdateDefault" = false;
                "extensions.update.enabled" = false;
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
                "security.protectionspopup.recordEventTelemetry" = false;
                "security.identitypopup.recordEventTelemetry" = false;
                "security.certerrors.recordEventTelemetry" = false;
                "security.app_menu.recordEventTelemetry" = false;
                "toolkit.telemetry.pioneer-new-studies-available" = false;
                "app.shield.optoutstudies.enable" = false;
              };

              privacy = {
                # clipboard events: https://superuser.com/questions/1595994/dont-let-websites-overwrite-clipboard-in-firefox-without-explicitly-giving-perm
                # Breaks copy/paste on websites
                #"dom.event.clipboardevents.enabled" = false;
                "dom.battery.enabled" = false;
                # "privacy.resistFingerprinting" = true;
              };

              https = {
                "dom.security.https_only_mode" = false;
                "dom.security.https_only_mode_ever_enabled" = false;
              };

              graphics = {
                "media.ffmpeg.vaapi.enabled" = true;
                "media.gpu-process-decoder" = true;
                "dom.webgpu.enabled" = true;
                "gfx.webrender.all" = true;
                "layers.mlgpu.enabled" = true;
                "layers.gpu-process.enabled" = true;
              };

              generalSettings = {
                "widget.use-xdg-desktop-portal.file-picker" = 2;
                "widget.use-xdg-desktop-portal.mime-handler" = 2;
                "browser.aboutConfig.showWarning" = false;
                "browser.tabs.warnOnClose" = true;
                "browser.tabs.warnOnCloseOtherTabs" = true;
                "browser.warnOnQuit" = true;
                "browser.shell.checkDefaultBrowser" = false;
                "extensions.htmlaboutaddons.inline-options.enabled" = false;
                "extensions.htmlaboutaddons.recommendations.enabled" = false;
                "extensions.pocket.enabled" = false;
                "browser.fullscreen.autohide" = false;
                "browser.contentblocking.category" = "standard";
                # "browser.display.use_document_fonts" = 0; Using enable-browser-fonts extension instead
                "xpinstall.signatures.required" = false; # for bypass-payawlls
              };

              toolbars = {
                "browser.tabs.firefox-view" = false;
                "browser.toolbars.bookmarks.visibility" = "newtab";
                "browser.download.autohideButton" = false;
              };

              passwords = {
                "signon.rememberSignons" = false;
                "signon.autofillForms" = false;
                "signon.generation.enabled" = false;
                "signon.management.page.breach-alerts.enabled" = false;
              };

              downloads = {
                "browser.download.useDownloadDir" = false;
                "browser.download.always_ask_before_handling_new_types" = true;
              };
            in
              generalSettings
              // passwords
              // extensions
              // https
              // newTab
              // searchBar
              // privacy
              // telemetry
              // graphics
              // downloads
              // toolbars;
          };
        };
      };
    }
  ]);
}
