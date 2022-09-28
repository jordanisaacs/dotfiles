{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.jd.ankisyncd;

  name = "ankisyncd";
in {
  options.jd.ankisyncd = {
    enable = mkOption {
      description = "Whether to enable ankisyncd";
      type = types.bool;
      default = false;
    };

    firewall = mkOption {
      type = types.enum ["world" "wg" "closed"];
      default = "closed";
      description = "Open firewall to everyone or wireguard";
    };

    address = mkOption {
      type = types.str;
      description = "Ankisyncd address";
      default = "127.0.0.1";
    };

    dataDir = mkOption {
      type = types.str;
      description = "Anki data directory";
      default = "/var/lib/${name}";
    };

    port = mkOption {
      type = types.int;
      description = "Ankisyncd port";
      default = 27701;
    };
  };

  config = mkIf (cfg.enable) (mkMerge [
    {
      ids = {
        uids = {
          ${name} = 326;
        };
        gids = {
          ${name} = 326;
        };
      };
      users = {
        groups = {
          ${name}.gid = config.ids.gids.ankisyncd;
        };
        users.${name} = {
          uid = config.ids.uids.ankisyncd;
          description = "Ankisyncd user";
          group = "ankisyncd";
        };
      };

      systemd.services.ankisyncd = {
        description = "ankisyncd - Anki sync server";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        path = [pkgs.ankisyncd];

        serviceConfig = {
          # Use my version of ankisyncd because the nixpkgs version is not compatible with up to date clients
          ExecStart = "${pkgs.jdpkgs.ankisyncd}/bin/ankisyncd";
          Type = "simple";
          User = name;
          Group = name;
          Restart = "always";
        };

        environment = {
          ANKISYNCD_HOST = cfg.address;
          ANKISYNCD_PORT = builtins.toString cfg.port;
          ANKISYNCD_DATA_ROOT = cfg.dataDir;
          ANKISYNCD_AUTH_DB_PATH = "${cfg.dataDir}/auth.db";
          ANKISYNCD_SESSION_DB_PATH = "${cfg.dataDir}/session.db";
          ANKISYNCD_BASE_URL = "/sync/";
          ANKISYNCD_BASE_MEDIA_URL = "/msync/";
        };
      };
    }
    (mkIf (cfg.firewall == "world") {
      networking.firewall.allowedTCPPorts = [cfg.port];
    })
    (
      let
        wgconf = config.jd.wireguard;
      in
        mkIf
        (cfg.firewall == "wg" && (assertMsg wgconf.enable "Wireguard must be enabled for wireguard ssh firewall"))
        {
          networking.firewall.interfaces.${wgconf.interface}.allowedTCPPorts = [cfg.port];
        }
    )
  ]);
}
