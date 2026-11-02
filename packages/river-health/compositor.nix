{ pkgs, river }:
river.overrideAttrs (old: {
  pname = "river-with-native-health";
  patches = (old.patches or [ ]) ++ [
    ./control-click.patch
    ./foreign-toplevel-lifetime.patch
    ./river-health.patch
  ];
  passthru = (old.passthru or { }) // {
    controlClick = true;
  };
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.wayland-scanner ];
  postPatch = (old.postPatch or "") + ''
    cp ${pkgs.wayland-protocols}/share/wayland-protocols/staging/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml protocol/
    cp ${./health-server.c} river/health-server.c
    cp ${./jd-window-health-v1.xml} protocol/jd-window-health-v1.xml
  '';
})
