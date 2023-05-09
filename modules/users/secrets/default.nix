{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.secrets;
  persist = config.jd.impermanence;
in {
  options.jd.secrets.identityPaths = mkOption {
    type = with types; listOf str;
    description = "The path to age identities (private key)";
  };

  config = mkMerge [
    {
      homeage = {
        identityPaths = cfg.identityPaths;
        pkg = pkgs.rage;
      };
    }
    (mkIf persist.enable {
      home.persistence.${persist.backupPool}.files = cfg.identityPaths;
    })
  ];
}
