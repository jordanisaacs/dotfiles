_final: prev:
let
  source = prev.applyPatches {
    name = "trayscale-ipn-watch-source";
    src = prev.trayscale.src;
    patches = [
      ./trayscale-ipn-watch.patch
      ./trayscale-netmon.patch
    ];
  };
in
{
  trayscale = prev.trayscale.overrideAttrs (_: {
    # Fix daemon compatibility and network-change monitoring with the pinned SDK.
    src = source;
  });
}
