{ pkgs }:
# Building the application runs pytest against the same project used by uv.
(import ../default.nix {
  inherit pkgs;
  modules = [ ./framework-policy.nix ];
}).cli
