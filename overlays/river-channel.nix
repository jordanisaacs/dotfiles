final: prev: {
  # Channel 0.4.1 targets Zig 0.16; nixpkgs' default 0.17 removed Build.args.
  # Keep upstream source and dependency hashes, selecting its supported compiler.
  river-channel = prev.river-channel.override { zig = final.zig_0_16; };
}
