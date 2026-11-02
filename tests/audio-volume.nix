{
  pkgs,
  home,
  stock ? false,
}:
let
  python = pkgs.python3.withPackages (packages: [
    packages.dbus-python
    packages.pygobject3
  ]);
in
pkgs.runCommand "audio-volume-${if stock then "uncapped" else "bounded"}"
  {
    nativeBuildInputs = [
      python
      pkgs.pipewire
      pkgs.wireplumber
      pkgs.pulseaudio
      pkgs.xvfb
      pkgs.dbus
      pkgs.systemd
      pkgs.pasystray
    ];
    GI_TYPELIB_PATH = "${pkgs.glib.out}/lib/girepository-1.0";
    PASYSTRAY_UNIT = home.xdg.configFile."systemd/user/pasystray.service".source;
    SOUND_TOOLS = "${pkgs.jdScripts.soundTools}/bin/stools";
    PASYSTRAY_STOCK_ENTRY = "${pkgs.pasystray}/etc/xdg/autostart/pasystray.desktop";
    PASYSTRAY_USER_ENTRY = "${home.xdg.configFile.autostart.source}/pasystray.desktop";
    XDG_GENERATOR = "${pkgs.systemd}/lib/systemd/user-generators/systemd-xdg-autostart-generator";
    DBUS_SESSION_CONFIG = "${pkgs.dbus}/share/dbus-1/session.conf";
  }
  ''
    python -B ${./test_audio_volume.py} --output "$out" ${pkgs.lib.optionalString stock "--stock"}
  ''
