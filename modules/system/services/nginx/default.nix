{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.jd.proxy;
in {
  options.jd.proxy = {
    enable = mkOption {
      description = "Whether to enable nginx reverse proxy";
      type = types.bool;
      default = false;
    };

    firewall = mkOption {
      type = types.enum ["world" "wg" "closed"];
      default = "closed";
      description = "What level firewall to open";
    };

    address = mkOption {
      type = types.str;
      description = "Proxy address";
      default = "127.0.0.1";
    };

    port = mkOption {
      type = types.int;
      description = "Proxy port";
      default = 80;
    };
  };

  config = mkIf (cfg.enable) (mkMerge [
    {
      services.nginx = {
        enable = true;
        recommendedProxySettings = true;

        virtualHosts."proxy" = {
          listen = [
            {
              addr = cfg.address;
              port = cfg.port;
            }
          ];

          locations = mkMerge [
            (mkIf (config.jd.miniflux.enable) {
              "/miniflux/" = {
                proxyPass = "http://${config.jd.miniflux.address}:${builtins.toString config.jd.miniflux.port}/miniflux/";
              };
            })
            (mkIf (config.jd.taskserver.enable) {
              "/taskserver/" = {
                proxyPass = "http://${config.jd.taskserver.address}:${builtins.toString config.jd.taskserver.port}/taskserver/";
              };
            })
            {
              "/status" = {
                extraConfig = ''
                  stub_status on;
                  access_log off;
                  allow ${cfg.address}/16;
                  deny all;
                '';
              };
            }
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
