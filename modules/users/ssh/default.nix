{
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

        settings."*" = {
          ForwardAgent = false;
          AddKeysToAgent = "yes";
          Compression = false;
          ServerAliveInterval = 0;
          ServerAliveCountMax = 3;
          HashKnownHosts = false;
          UserKnownHostsFile = "~/.ssh/known_hosts";
          ControlMaster = "no";
          ControlPath = "~/.ssh/master-%r@%n:%p";
          ControlPersist = "no";
        };
      };
    }
    (mkIf config.jd.impermanence.enable {
      home.persistence.${config.jd.impermanence.backupPool}.directories = [ ".ssh" ];
    })
  ]);
}
