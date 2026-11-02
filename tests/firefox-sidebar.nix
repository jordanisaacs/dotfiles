{
  pkgs,
  home,
  withHover ? true,
  withCompactStyle ? true,
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
    FONTCONFIG_FILE = pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; };
  }
  ''
    python -B ${./test_firefox_sidebar.py}
    touch "$out"
  ''
