{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.jd.graphical.applications;
  isGraphical = let cfg = config.jd.graphical;
  in cfg.xorg.enable || cfg.wayland.enable;
in {
  options.jd.graphical.applications.dolphin = {
    enable = mkEnableOption "dolphin file explorer";
  };

  config = mkIf (isGraphical && cfg.enable && cfg.dolphin.enable) {
    home.packages = with pkgs; [
      # Dolphin + Plugins
      # Dolphin is patched to remove plasma-dolphin.service and dbus-reliance on it.
      # This is because it requires `background.slice` which is kde specific.
      # Without the slice, systemd will kill the dolphin application immediately
      kdePackages.ffmpegthumbs
      kdePackages.kdegraphics-thumbnailers
      kdePackages.kio-extras
      kdePackages.phonon
      kdePackages.phonon-vlc # TODO: package phonon-mpv
      kdePackages.dolphin-plugins
      (runCommand "dolphin-nokde" { } ''
        mkdir $out
        cp -Rsp ${kdePackages.dolphin}/* $out

        # Remove kde requirement for starting dbus
        chmod +w $out/share/dbus-1/services/
        rm $out/share/dbus-1/services/org.kde.dolphin.FileManager1.service
        head -n -1 ${kdePackages.dolphin}/share/dbus-1/services/org.kde.dolphin.FileManager1.service \
          > $out/share/dbus-1/services/org.kde.dolphin.FileManager1.service
        chmod -w $out/share/dbus-1/services

        chmod +w $out/share/systemd/user
        rm $out/share/systemd/user/plasma-dolphin.service
      '') # fixes dbus/firefox
    ];

    xdg.mimeApps = {
      associations.added = {
        "x-scheme-handler/file" = "org.kde.dolphin.desktop";
        "x-directory/normal" = "org.kde.dolphin.desktop";
      };

      defaultApplications = {
        "inode/directory" = "org.kde.dolphin.desktop";
        "x-directory/normal" = "org.kde.dolphin.desktop";
        "x-scheme-handler/file" = "org.kde.dolphin.desktop";
      };
    };
  };
}
