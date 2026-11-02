# app-rummage 1.2 stops before UWSM's nested graphical app slice. Keep the
# upstream package and dependencies, with a focused traversal/attribution fix.
final: prev: {
  mission-center = prev.mission-center.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./mission-center-uwsm-apps.patch ];
    passthru = (old.passthru or { }) // {
      tests = (old.passthru.tests or { }) // {
        uwsm-apps = import ../tests/mission-center-apps.nix {
          pkgs = final;
          missionCenter = prev.mission-center;
        };
      };
    };
  });
}
