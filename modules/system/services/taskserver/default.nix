{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.jd.taskserver;
in {
  options.jd.taskserver = {
    enable = mkOption {
      description = "Whether to enable miniflux";
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
      description = "Taskserver address";
      default = "127.0.0.1";
    };

    fqdn = mkOption {
      type = types.str;
      description = "fqdn for certificates";
    };

    port = mkOption {
      type = types.int;
      description = "Taskserver port";
      default = 53589;
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/taskserver";
    };
  };

  config = mkIf (cfg.enable) (mkMerge [
    {
      services = {
        taskserver = {
          enable = true;
          trust = "strict";
          fqdn = cfg.fqdn;
          listenHost = cfg.address;
          listenPort = cfg.port;
          dataDir = cfg.dataDir;
          organisations."people".users = [
            "jd"
          ];
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
