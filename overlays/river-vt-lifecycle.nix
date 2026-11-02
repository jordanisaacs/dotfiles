_final: prev: {
  # A destroyed backend output may remain in the WM's scheduled output list
  # until its next manage sequence. Layer clients must not inherit its null
  # wlroots output while changing virtual terminals.
  river = prev.river.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./river-vt-lifecycle.patch ];
  });
}
