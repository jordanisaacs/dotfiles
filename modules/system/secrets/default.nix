{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.secrets;
  inherit (config.jd.impermanence.persistedDatasets.root) backup;
in
{
  options.jd.secrets.identityPaths = mkOption {
    type = with types; listOf str;
    description = "The path to age identities (private key)";
  };

  config = mkMerge [
    {
      age.identityPaths = cfg.identityPaths;
    }
    (mkIf config.jd.impermanence.enable {
      environment.persistence.${backup}.files = cfg.identityPaths;
    })
  ];
}
