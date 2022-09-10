{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.secrets;
in {
  options.jd.secrets.identityPaths = mkOption {
    type = with types; listOf str;
    description = "The path to age identities (private key)";
  };

  config = {
    homeage = {
      identityPaths = cfg.identityPaths;
      pkg = pkgs.rage;
    };
  };
}
