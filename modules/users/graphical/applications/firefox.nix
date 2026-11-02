{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.graphical.applications;
  firefoxPkg =
    if cfg.firefox.useDevEdition then pkgs.firefox-devedition-unwrapped else pkgs.firefox-unwrapped;
  # The flake's NUR revision owns these versions, including Kagi and LanguageTool.
  # Keep Cookie AutoDelete's existing extension ID and profile storage intact.
  addons =
    with pkgs.nur.repos.rycee.firefox-addons;
    [
      kagi-search
      languagetool
      user-agent-string-switcher
      redirector
      rust-search-extension
      bitwarden
      ublock-origin
      multi-account-containers
      clearurls
      cookie-autodelete
      sponsorblock
      return-youtube-dislikes
    ]
    ++ optional cfg.firefox.videoDownloader video-downloadhelper
    ++ optional cfg.firefox.vim.enable tridactyl
    ++ optional config.jd.applications.activitywatch.enable aw-watcher-web;
in
{
  options.jd.graphical.applications.firefox = {
    enable = mkEnableOption "Firefox with the personal profile";

    useDevEdition = mkOption {
      type = types.bool;
      default = false;
      description = "Use Firefox Developer Edition.";
    };

    videoDownloader = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Video DownloadHelper (version 10+ needs no native companion).";
    };

    vim.enable = mkEnableOption "Tridactyl Vim navigation";
  };

  config = mkIf cfg.firefox.enable (mkMerge [
    (mkIf config.jd.impermanence.enable {
      home.persistence.${config.jd.impermanence.persistPool} = [ ".mozilla" ];
    })
    {
      home.file.".mozilla/firefox/ignore-dev-edition-profile".text = "";

      xdg.mimeApps.defaultApplications = {
        "application/xhtml+xml" = "firefox.desktop";
        "application/xhtml_xml" = "firefox.desktop";
        "text/html" = "firefox.desktop";
        "x-scheme-handler/http" = "firefox.desktop";
        "x-scheme-handler/https" = "firefox.desktop";
      };

      programs.firefox = {
        enable = true;
        # Retain the existing profile, bookmarks, accounts and extension storage.
        configPath = ".mozilla/firefox";
        package = pkgs.wrapFirefox firefoxPkg {
          nativeMessagingHosts = optional cfg.firefox.vim.enable pkgs.tridactyl-native;
        };

        # Supported Firefox enterprise policies, rather than obsolete user.js lists.
        # https://firefox-admin-docs.mozilla.org/reference/policies/
        policies = {
          # Firefox 149.0.2+: blocks every built-in AI feature, including translations,
          # PDF alt text, summaries, smart tabs/windows, speech and sidebar chat.
          # https://firefox-admin-docs.mozilla.org/reference/policies/aicontrols/
          AIControls.Default = {
            Value = "blocked";
            Locked = true;
          };
          DisableTelemetry = true;
          DisableFirefoxStudies = true;
          # Disable Nimbus feature rollouts; security Remote Settings stay enabled.
          DisableRemoteImprovements = true;
          DontCheckDefaultBrowser = true;
          HttpsOnlyMode = "enabled";
          EnableTrackingProtection.Category = "standard";
          FirefoxHome = {
            Search = false;
            TopSites = true;
            Highlights = true;
            Stories = false;
            SponsoredTopSites = false;
            SponsoredStories = false;
            Weather = false;
            Widgets.Enabled = false;
          };
          FirefoxSuggest = {
            WebSuggestions = false;
            SponsoredSuggestions = false;
            ImproveSuggest = false;
            OnlineEnabled = false;
            Locked = true;
          };
          UserMessaging = {
            ExtensionRecommendations = false;
            FeatureRecommendations = false;
            MoreFromMozilla = false;
            FirefoxLabs = false;
            UrlbarInterventions = false;
            SkipOnboarding = true;
          };
          # Bitwarden handles credentials and autofill.
          OfferToSaveLogins = false;
          AutofillAddressEnabled = false;
          AutofillCreditCardEnabled = false;
          PromptForDownloadLocation = true;

          # Nix updates managed add-ons; user-installed add-ons can still update.
          # https://firefox-admin-docs.mozilla.org/reference/policies/extensionsettings/
          ExtensionSettings = listToAttrs (
            map (addon: nameValuePair addon.addonId { updates_disabled = true; }) addons
          );

          # Removing a user.js entry alone leaves its old value in prefs.js.
          # Clear our old graphics/debugging overrides so Firefox selects supported
          # acceleration and secure defaults on this hardware after migration.
          # https://firefox-admin-docs.mozilla.org/reference/policies/preferences/
          Preferences =
            genAttrs
              [
                "media.ffmpeg.vaapi.enabled"
                "media.gpu-process-decoder"
                "dom.webgpu.enabled"
                "gfx.webrender.all"
                "layers.mlgpu.enabled"
                "layers.gpu-process.enabled"
                "devtools.chrome.enabled"
                "devtools.debugger.remote-enabled"
                "toolkit.legacyUserProfileCustomizations.stylesheets"
              ]
              (_: {
                Status = "clear";
              });
        };

        profiles.personal = {
          id = 0;
          extensions.packages = addons;
          settings = {
            # Native vertical tabs: no tree-tab extension or fragile userChrome.
            # Firefox source: browser/app/profile/firefox.js, sidebar preferences.
            "sidebar.revamp" = true;
            "sidebar.verticalTabs" = true;
            "extensions.activeThemeID" = "default-theme@mozilla.org";

            # Migrate the old globally disabled updates and unsigned-add-on override.
            "extensions.update.autoUpdateDefault" = true;
            "extensions.update.enabled" = true;
            "xpinstall.signatures.required" = true;
            "dom.security.https_only_mode" = true;
            "privacy.globalprivacycontrol.enabled" = true;

            "widget.use-xdg-desktop-portal.file-picker" = 2;
            "widget.use-xdg-desktop-portal.mime-handler" = 2;
            "browser.fullscreen.autohide" = false;
            "browser.link.open_newwindow" = 1;
            "browser.link.open_newwindow.override.external" = 3;
            "browser.warnOnQuit" = true;
            "browser.warnOnQuitShortcut" = true;
            "browser.tabs.warnOnClose" = true;
            "browser.tabs.warnOnCloseOtherTabs" = true;
            "browser.toolbars.bookmarks.visibility" = "newtab";
            "browser.download.autohideButton" = false;
            "browser.download.always_ask_before_handling_new_types" = true;
            "signon.autofillForms" = false;
            "signon.generation.enabled" = false;
            "cookiebanners.service.mode" = 1;
            "cookiebanners.service.mode.privateBrowsing" = 1;
          };
        };
      };
    }
  ]);
}
