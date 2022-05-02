{
  pkgs,
  config,
  lib,
  ...
}:
with lib; {
  config = {
    homeage.identityPaths = ["~/.ssh/id_ed25519"];
  };
}
