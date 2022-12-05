{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.impermanence;
in {
  options.jd.impermanence = {
    enable = mkOption {
      description = "Whether to enable impermanence";
      type = types.bool;
      default = false;
    };

    type = mkOption {
      description = "Whether is SSH client or server";
      type = types.enum ["client" "server"];
      default = "client";
    };

    authorizedKeyFiles = mkOption {
      description = "Authorized ssh keys";
      type = types.listOf types.str;
      default = "";
    };
  };

  config = let
    impermanence = mkMerge [
      (mkIf (config.jd.boot.type == "zfs") {
        # Erase zfs pools on boot
        boot.initrd.postDeviceCommands = lib.mkAfter ''
          zfs rollback -r rpool/local/root@blank
          zfs rollback -r rpool/local/home@blank
        '';

        environment.persistence."/persist".directories = mkIf (config.jd.ssh.enable && config.jd.ssh.type == "server") [
          "/etc/secrets/initrd"
        ];
      })
      {
        environment.persistence."/persist" = {
          hideMounts = true;
          files = config.jd.secrets.identityPaths;
        };

        environment.persistence."/persist/data" = mkMerge [
          {
            hideMounts = true;
          }
          (mkIf (config.services.postgresql.enable) {
            directories = [config.services.postgresql.dataDir];
          })
          (mkIf (config.mailserver.enable) {
            directories = [
              config.mailserver.mailDirectory
              config.mailserver.indexDir
              config.mailserver.dkimKeyDirectory
              config.mailserver.sieveDirectory
              "/var/lib/acme"
            ];
          })
          (mkIf (config.jd.taskserver.enable) {
            directories = [config.jd.taskserver.dataDir];
          })
          (mkIf (config.jd.ankisyncd.enable) {
            directories = [
              {
                directory = config.jd.ankisyncd.dataDir;
                user = "ankisyncd";
                group = "ankisyncd";
                mode = "0700";
              }
            ];
          })
          (mkIf (config.jd.microbin.enable) {
            directories = [
              {
                directory = "/var/lib/microbin";
                user = "microbin";
                group = "microbin";
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
      }
      {
        # Wait to acivate age decryption until mounted
        system.activationScripts.agenixInstall.deps = ["specialfs" "persist-files"];
      }
    ];
  in
    mkIf cfg.enable impermanence;
}
