{ pkgs, home }:
let
  configRoot = pkgs.linkFarm "desktop-font-config" (
    map
      (name: {
        inherit name;
        path = home.xdg.configFile.${name}.source;
      })
      [
        "ghostty/config"
        "fuzzel/fuzzel.ini"
        "waybar/style.css"
        "gtk-3.0/settings.ini"
      ]
  );
in
pkgs.runCommand "desktop-font-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    XDG_CONFIG_HOME = configRoot;
    GHOSTTY = pkgs.lib.getExe home.programs.ghostty.package;
    FUZZEL = pkgs.lib.getExe home.programs.fuzzel.package;
    FONT_POINTS = toString home.gtk.font.size;
    TERMINAL_FONT_POINTS = toString home.programs.ghostty.settings.font-size;
    TERMINAL_PREFERRED_FONT_POINTS = toString home.jd.graphical.wayland.terminal.preferredFontSize;
    OUTPUT_SCALE = toString (
      if home.jd.graphical.wayland.display.enable then
        home.jd.graphical.wayland.display.internalScale
      else
        1.0
    );
    LAUNCHER_FONT = home.programs.fuzzel.settings.main.font;
    MONOSPACE_FONT = builtins.head home.fonts.fontconfig.defaultFonts.monospace;
    NORMAL_FONT = home.gtk.font.name;
    GTK_TEXT_SCALE = toString home.dconf.settings."org/gnome/desktop/interface".text-scaling-factor;
  }
  ''
    python -B ${./test_desktop_fonts.py}
    touch "$out"
  ''
