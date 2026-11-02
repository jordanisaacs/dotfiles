{
  pkgs,
  home,
  withHover ? true,
  withCompactStyle ? true,
  withStableRows ? true,
}:
pkgs.runCommand "firefox-sidebar-behavior-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    FIREFOX_BINARY = "${home.programs.firefox.finalPackage}/bin/firefox";
    FIREFOX_USER_JS = home.home.file.".mozilla/firefox/personal/user.js".source;
    FIREFOX_USER_CHROME = home.home.file.".mozilla/firefox/personal/chrome/userChrome.css".source;
    GECKODRIVER = "${pkgs.geckodriver}/bin/geckodriver";
    EXPECT_HOVER = if withHover then "1" else "0";
    INSTALL_COMPACT_STYLE = if withCompactStyle then "1" else "0";
    STABLE_COMPACT_ROWS = if withStableRows then "1" else "0";
    FIREFOX_UI_FONT_FAMILY = home.jd.graphical.applications.firefox.ui.fontFamily;
    FIREFOX_UI_FONT_SIZE_PX = toString (
      home.jd.graphical.applications.firefox.ui.fontSize * 96.0 / 72.0
    );
    FIREFOX_UI_SCALE_PERCENT = toString home.jd.graphical.applications.firefox.ui.scalePercent;
    FONTCONFIG_FILE = pkgs.makeFontsConf {
      # Include generic-family aliases in the sandbox just as the host does.
      includes = [ "${pkgs.fontconfig.out}/etc/fonts/conf.d" ];
      fontDirectories = [
        pkgs.dejavu_fonts
      ]
      ++ pkgs.lib.optional (home.gtk.font.package != null) home.gtk.font.package;
    };
  }
  ''
    python -B ${./test_firefox_sidebar.py}
    touch "$out"
  ''
