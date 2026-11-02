# Check native I/O failures and terminate EDID strings in Gamescope 3.17.0.
# Preserve compiler diagnostics and the package's existing features and tests.
_final: prev: {
  gamescope = prev.gamescope.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./gamescope-errors.patch ];
    doCheck = true;
  });
}
