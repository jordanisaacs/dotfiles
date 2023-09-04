{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.impermanence;

  datasets = { name, ... }: {
    options = {
      persist = mkOption {
        description = "Location of the persist dataset";
        type = types.str;
        default = "/persist/${name}";
      };

      backup = mkOption {
        description = "Location of the backup dataset";
        type = types.str;
        default = "/backup/${name}";
      };
    };
  };
in
{
  options.jd.impermanence = {
    enable = mkOption {
      description = "Whether to enable impermanence. Requires ZFS";
      type = types.bool;
      default = false;
    };

    rollbackDatasets = mkOption {
      description = "Names of the erase your darling datasets, ones that are rollback to @blank snapshot on boot";
      type = with types; listOf str;
      default = [ ];
    };

    persistedDatasets = mkOption {
      description = "Names of the persisted datasets which all have a persist and backup";
      type = with types; attrsOf (submodule datasets);
      default = { };
    };
  };

  config =
    let
      zfs = {
        boot.initrd.postDeviceCommands =
          lib.mkAfter
            (concatMapStringsSep
              "\n"
              (d: "zfs rollback -r ${d}@blank")
              cfg.rollbackDatasets);
      };

      impermanence = {
        environment.persistence =
          concatMapAttrs
            # persist can be equal to backup, quick and easy to way ensure no merge issues (just overrides)
            (n: v:
              {
                ${v.persist} = {
                  hideMounts = true;
                };
              }
              // {
                ${v.backup} = {
                  hideMounts = true;
                };
              })
            cfg.persistedDatasets;

        # Wait to acivate age decryption until mounted
        system.activationScripts.agenixNewGeneration.deps = [ "specialfs" "persist-files" ];
      };

      # TODO: Refactor out
      apps = {
        environment.persistence.${cfg.persistedDatasets.data.backup} = mkMerge [
          (mkIf config.services.postgresql.enable {
            directories = [ config.services.postgresql.dataDir ];
          })
          (mkIf config.mailserver.enable {
            directories = [
              config.mailserver.mailDirectory
              config.mailserver.indexDir
              config.mailserver.dkimKeyDirectory
              config.mailserver.sieveDirectory
              "/var/lib/acme"
            ];
          })
          (mkIf config.jd.taskserver.enable {
            directories = [ config.jd.taskserver.dataDir ];
          })
          (mkIf config.jd.ankisyncd.enable {
            directories = [
              {
                directory = config.jd.ankisyncd.dataDir;
                user = "ankisyncd";
                group = "ankisyncd";
                mode = "0700";
              }
            ];
          })
          (mkIf (config.jd.calibre.web.enable || config.jd.calibre.server.enable) {
            directories = [
              {
                directory = "/var/lib/calibre-lib";
                user = "calibre";
                group = "calibre";
                mode = "0700";
              }
            ];
          })
          (mkIf config.jd.calibre.web.enable {
            directories = [
              {
                directory = "/var/lib/calibre-web";
                user = "calibre";
                group = "calibre";
                mode = "0700";
              }
            ];
          })
          (mkIf config.jd.syncthing.relay.enable {
            directories = [
              {
                directory = "/var/strelaysv";
                user = "syncthing-relay";
                group = "syncthing-relay";
                mode = "0700";
              }
            ];
          })
          (mkIf config.jd.syncthing.discovery.enable {
            directories = [
              {
                directory = "/var/stdiscosrv";
                user = "syncthing-discovery";
                group = "syncthing-discovery";
                mode = "0700";
              }
            ];
          })
        ];
      };

      mergeConfig = mkMerge [ zfs impermanence apps ];
    in
    mkIf cfg.enable mergeConfig;
}
