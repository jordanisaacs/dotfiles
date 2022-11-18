{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  conf = config.jd.syncthing;
in {
  options.jd.syncthing = {
    relay = {
      enable = mkOption {
        description = "Whether to enable microbin";
        type = types.bool;
        default = false;
      };

      address = mkOption {
        type = types.str;
        description = "Syncthing relay address";
        default = "10.55.0.2";
      };

      port = mkOption {
        type = types.int;
        description = "Syncthing relay port";
        default = 22067;
      };

      statusPort = mkOption {
        type = types.int;
        description = "Syncthing relay port";
        default = 22070;
      };
    };

    discovery = {
      enable = mkOption {
        description = "Whether to enable microbin";
        type = types.bool;
        default = false;
      };

      address = mkOption {
        type = types.str;
        description = "Syncthing relay address";
        default = "10.55.0.2";
      };

      port = mkOption {
        type = types.int;
        description = "Syncthing relay port";
        default = 2300;
      };
    };
  };

  config = mkMerge [
    (let
      cfg = conf.relay;
    in
      mkIf cfg.enable {
        users.groups."syncthing-relay" = {};

        users.users = {
          syncthing-relay = {
            name = "syncthing-relay";
            #uid = config.ids.uids.calibre-server;
            group = "syncthing-relay";
            isSystemUser = true;
          };
        };

        services.syncthing.relay = {
          enable = true;
          listenAddress = cfg.address;
          statusListenAddress = cfg.address;
          port = cfg.port;
          statusPort = cfg.statusPort;

          pools = [""];
          extraOptions = [
            "-keys=/var/strelaysv"
          ];
        };

        systemd.services.syncthing-relay.serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = "syncthing-relay";
        };

        networking.firewall.interfaces.${config.jd.wireguard.interface}.allowedTCPPorts =
          mkIf
          (assertMsg config.jd.wireguard.enable "Wireguard must be enable for wireguard ssh firewall")
          [cfg.port cfg.statusPort];
      })
    (let
      cfg = conf.discovery;
    in
      mkIf cfg.enable {
        users.groups."syncthing-discovery" = {};

        users.users = {
          syncthing-discovery = {
            name = "syncthing-discovery";
            group = "syncthing-discovery";
            isSystemUser = true;
          };
        };

        networking.firewall.interfaces.${config.jd.wireguard.interface}.allowedTCPPorts =
          mkIf
          (assertMsg config.jd.wireguard.enable "Wireguard must be enable for wireguard ssh firewall")
          [cfg.port];

        systemd.services.syncthing-discovery = {
          description = "Syncthing relay server";
          wantedBy = ["multi-user.target"];
          after = ["network.target"];

          serviceConfig = {
            ExecStart = ''
              ${pkgs.syncthing-discovery}/bin/stdiscosrv \
                -db-dir=/run/stdiscosrv/ -replicate="" \
                -key="/var/stdiscosrv/key.pem" \
                -cert="/var/stdiscosrv/cert.pem" \
                -listen=${cfg.address}:${builtins.toString cfg.port} -debug
            '';
            RuntimeDirectory = "stdiscosrv";
            Type = "simple";
            DynamicUser = true;
            Restart = "on-failure";
          };
        };
      })
  ];
}
