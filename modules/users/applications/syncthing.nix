{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.applications.syncthing;
  isGraphical =
    let
      inherit (config.jd) graphical;
    in
    graphical.xorg.enable || graphical.wayland.enable;
  syncthingtrayv2 = pkgs.runCommand "syncthingtray-fixed" { } ''
    mkdir $out
    cp -rs ${pkgs.syncthingtray}/* $out

    chmod +w $out/lib
    chmod +w $out/lib/qt-5
    rm $out/lib/qt-5/libsyncthingfileitemaction.a

    mkdir -p $out/lib/qt-5.15.8/plugins
    ln -s ${pkgs.syncthingtray}/lib/qt-5/libsyncthingfileitemaction.a $out/lib/qt-5.15.8/plugins/
  '';

  syncthingtray = pkgs.syncthingtray.overrideAttrs (_: {
    buildInputs = with pkgs; [
      libsForQt5.qt5.qtbase
      cpp-utilities
      libsForQt5.qtutilities
      boost
      libsForQt5.qtforkawesome
      libsForQt5.plasma-framework
    ];

    nativeBuildInputs = with pkgs; [
      cmake
      libsForQt5.qt5.qttools
      libsForQt5.qt5.wrapQtAppsHook
    ];

    cmakeFlags = [
      "-DAUTOSTART_EXEC_PATH=syncthingtray"
      # See https://github.com/Martchus/syncthingtray/issues/42
      "-DQT_PLUGIN_DIR:STRING=${placeholder "out"}/lib/qt-5.15.8/plugins"
      "-DNO_PLASMOID=ON"
      "-DSYSTEMD_SUPPORT=ON"
      "-DWEBVIEW_PROVIDER:STRING=none"
      "-DBUILD_SHARED_LIBS=1"
    ];
  });
in
{
  options.jd.applications.syncthing = {
    enable = mkOption {
      description = "Enable syncthing";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (config.jd.applications.enable && cfg.enable) {
    services.syncthing = {
      enable = true;
      # TODO: fails on service starting during login. Restarting it sets it up correctly
      tray.enable = false;
    };

    home.packages = [ syncthingtray ];

    systemd.user.services = {
      "syncthingtray" = {
        Unit = {
          Description = "syncthingtray";
          Requires = [ "tray.target" ];
          After = [ "graphical-session-pre.target" "tray.target" ];
          PartOf = [ "graphical-session.target" ];
        };

        Service = {
          # Shitty hack to make syncthingtray wait until tray is initialized
          # --wait does not work on wayland due to:
          # QObject::connect: No such signal QPlatformNativeInterface::systemTrayWindowChanged(QScreen*)
          ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
          ExecStart = "${syncthingtray}/bin/syncthingtray";
        };

        Install = { WantedBy = [ "tray.target" ]; };
      };
    };
  };
}
