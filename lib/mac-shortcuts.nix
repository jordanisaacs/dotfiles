{
  # Explicit app identities avoid interpreting editor/terminal control prefixes
  # or GTK Emacs text navigation as ordinary application accelerators.
  applications = [
    "org.kde.dolphin"
    "dolphin"
    # Chromium/Electron GTK editing needs its own native-app verification
    # before adding it here; Control+A can mean Emacs beginning-of-line.
    "io.missioncenter.MissionCenter"
  ];
  applicationShortcuts = [
    {
      name = "Firefox text navigation";
      applications = [
        "firefox"
        "org.mozilla.firefox"
      ];
      # Firefox owns native Command accelerators through ui.key.accelKey.
      # Only Option/line-navigation differences need evdev translation.
      shortcuts = {
        "Alt-Left" = "Ctrl-Left";
        "Alt-Right" = "Ctrl-Right";
        "Alt-Shift-Left" = "Ctrl-Shift-Left";
        "Alt-Shift-Right" = "Ctrl-Shift-Right";
        "Alt-Backspace" = "Ctrl-Backspace";
        "Alt-Delete" = "Ctrl-Delete";
        "Super-Left" = "Home";
        "Super-Right" = "End";
        "Super-Shift-Left" = "Shift-Home";
        "Super-Shift-Right" = "Shift-End";
        "Super-Up" = "Ctrl-Home";
        "Super-Down" = "Ctrl-End";
        "Super-Shift-Up" = "Ctrl-Shift-Home";
        "Super-Shift-Down" = "Ctrl-Shift-End";
        "Super-LeftBrace" = "Alt-Left";
        "Super-RightBrace" = "Alt-Right";
      };
    }
    {
      name = "Dolphin settings";
      applications = [
        "org.kde.dolphin"
        "dolphin"
      ];
      shortcuts."Super-comma" = "Ctrl-Shift-comma";
    }
  ];
  shortcuts = {
    "Super-c" = "Ctrl-c";
    "Super-v" = "Ctrl-v";
    "Super-x" = "Ctrl-x";
    "Super-a" = "Ctrl-a";
    "Super-z" = "Ctrl-z";
    "Super-Shift-z" = "Ctrl-Shift-z";
    "Super-w" = "Ctrl-w";
    "Super-Shift-w" = "Ctrl-Shift-w";
    "Super-q" = "Ctrl-q";
    "Super-n" = "Ctrl-n";
    "Super-Shift-n" = "Ctrl-Shift-n";
    "Super-t" = "Ctrl-t";
    "Super-Shift-t" = "Ctrl-Shift-t";
    "Super-l" = "Ctrl-l";
    "Super-f" = "Ctrl-f";
    "Super-s" = "Ctrl-s";
    "Super-Shift-s" = "Ctrl-Shift-s";
    "Super-o" = "Ctrl-o";
    "Super-r" = "Ctrl-r";
    "Super-p" = "Ctrl-p";
    "Super-Shift-p" = "Ctrl-Shift-p";
    "Super-Shift-v" = "Ctrl-Shift-v";
    "Alt-Left" = "Ctrl-Left";
    "Alt-Right" = "Ctrl-Right";
    "Alt-Shift-Left" = "Ctrl-Shift-Left";
    "Alt-Shift-Right" = "Ctrl-Shift-Right";
    "Alt-Backspace" = "Ctrl-Backspace";
    "Alt-Delete" = "Ctrl-Delete";
    "Super-Left" = "Home";
    "Super-Right" = "End";
    "Super-Shift-Left" = "Shift-Home";
    "Super-Shift-Right" = "Shift-End";
    "Super-Up" = "Ctrl-Home";
    "Super-Down" = "Ctrl-End";
    "Super-Shift-Up" = "Ctrl-Shift-Home";
    "Super-Shift-Down" = "Ctrl-Shift-End";
    "Super-LeftBrace" = "Alt-Left";
    "Super-RightBrace" = "Alt-Right";
    "Super-Shift-LeftBrace" = "Ctrl-Shift-Tab";
    "Super-Shift-RightBrace" = "Ctrl-Tab";
    "Super-1" = "Ctrl-1";
    "Super-2" = "Ctrl-2";
    "Super-3" = "Ctrl-3";
    "Super-4" = "Ctrl-4";
    "Super-5" = "Ctrl-5";
    "Super-6" = "Ctrl-6";
    "Super-7" = "Ctrl-7";
    "Super-8" = "Ctrl-8";
    "Super-9" = "Ctrl-9";
  };
}
