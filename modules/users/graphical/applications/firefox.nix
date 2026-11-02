{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.graphical.applications;
  ui = cfg.firefox.ui;
  # Gecko's native system-font overrides use CSS pixels, not GTK points.
  # See widget/nsXPLookAndFeel.cpp, LookAndFeel::GetFont().
  uiFontSizePx = toString (ui.fontSize * 96.0 / 72.0);
  uiFontRoles = [
    "caption"
    "icon"
    "menu"
    "message-box"
    "small-caption"
    "status-bar"
    "-moz-pull-down-menu"
    "-moz-button"
    "-moz-list"
    "-moz-field"
  ];
  uiFontPreferences = listToAttrs (
    concatMap (role: [
      (nameValuePair "ui.font.${role}" ui.fontFamily)
      (nameValuePair "ui.font.${role}.size" uiFontSizePx)
    ]) uiFontRoles
  );
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

    ui = {
      fontFamily = mkOption {
        type = types.str;
        default = if config.gtk.font == null then "sans-serif" else config.gtk.font.name;
        description = "Firefox interface font family; inherits the normal desktop UI font.";
      };
      fontSize = mkOption {
        type = types.ints.positive;
        default = 11;
        description = "Firefox interface font size in points, independent of the desktop UI size.";
      };
      scalePercent = mkOption {
        type = types.ints.positive;
        default = 110;
        description = "Firefox pixel scale as a percentage, on top of each monitor's compositor scale.";
      };
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
          # Disable the profile-management UI even for profiles with an existing
          # store ID; browser.profiles.enabled alone is ignored in that case.
          # Existing personal-profile data and its normal startup stay intact.
          BlockAboutProfiles = true;
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
                # A fixed override would defeat automatic per-monitor scaling.
                "layout.css.devPixelsPerPx"
                "devtools.chrome.enabled"
                "devtools.debugger.remote-enabled"
              ]
              (_: {
                Status = "clear";
              });
        };

        profiles.personal = {
          id = 0;
          extensions.packages = addons;
          # Firefox 159's vertical tabs keep a 32px minimum in native compact
          # mode. Override only row sizing here; the native hover/pin UI owns
          # sidebar width and behavior.
          userChrome = ''
            @-moz-document url("chrome://browser/content/browser.xhtml") {
              @media -moz-pref("sidebar.verticalTabs") {
                :root[uidensity="compact"] #tabbrowser-tabs {
                  /* Reserve label line height even while labels are hidden.
                   * Otherwise expanding the rail grows rows under the pointer. */
                  --tab-min-height: max(28px, calc(var(--tab-label-line-height) * 1em));
                  --tab-margin-block: 0px;
                }
              }
            }
          '';
          settings = uiFontPreferences // {
            # Native pixel zoom composes with the monitor's scale; unlike a
            # positive devPixelsPerPx override it keeps per-monitor adaptation.
            # See widget/Screen.cpp, Screen::GetDefaultCSSScaleFactor().
            "ui.textScaleFactor" = ui.scalePercent;
            "browser.display.os-zoom-behavior" = 1;

            # Native vertical tabs; the small stylesheet above adjusts spacing.
            # Firefox source: browser/app/profile/firefox.js, sidebar preferences.
            "sidebar.revamp" = true;
            "sidebar.verticalTabs" = true;
            # Keep the icon rail visible; expand tab labels only while hovered.
            # Firefox's toolbar sidebar button can pin labels open; clicking it
            # again restores hover mode without changing these preferences.
            "sidebar.visibility" = "expand-on-hover";
            "sidebar.expandOnHover" = true;
            "browser.uidensity" = 1;
            "browser.compactmode.show" = true;
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
            "identity.fxaccounts.toolbar.enabled" = false;
            "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
            "layout.css.prefers-color-scheme.content-override" = 0;

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
