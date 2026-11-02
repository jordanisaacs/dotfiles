final: _prev: {
  river-health = import ../packages/river-health { pkgs = final; };
  # Keep the candidate explicit until the combined desktop/VT tests and parent
  # review approve activation. This extends, rather than replaces, both existing
  # River lifecycle and synchronized virtual-keyboard fixes.
  river-reka-with-health = import ../packages/river-health/compositor.nix {
    pkgs = final;
    river = final.river-reka;
  };
}
