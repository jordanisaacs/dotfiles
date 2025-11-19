{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.ssh;
in
{
  options.jd.ssh = {
    enable = mkOption {
      description = "enable ssh";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;

        matchBlocks."*" = {
          forwardAgent = false;
          addKeysToAgent = "yes";
          compression = false;
          serverAliveInterval = 0;
          serverAliveCountMax = 3;
          hashKnownHosts = false;
          userKnownHostsFile = "~/.ssh/known_hosts";
          controlMaster = "no";
          controlPath = "~/.ssh/master-%r@%n:%p";
          controlPersist = "no";
        };
      };
    }
    (mkIf config.jd.impermanence.enable {
      home.persistence.${config.jd.impermanence.backupPool}.directories = [ ".ssh" ];
    })
  ]);
}
