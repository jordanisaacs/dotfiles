_final: prev: {
  xremap = prev.xremap.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./xremap-session-guard.patch ];
    passthru = (old.passthru or { }) // {
      unpatched = prev.xremap;
      sessionGuarded = true;
    };
  });
}
