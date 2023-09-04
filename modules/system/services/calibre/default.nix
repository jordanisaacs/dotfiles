{ config
, lib
, pkgs
, ...
}:
with lib; let
  cfg = config.jd.calibre;

  enable = cfg.web.enable || cfg.server.enable;

  name = "calibre";
  user = name;
  group = name;
  id = 328;

  libraryDir = "/var/lib/calibre-lib";
in
{
  options.jd.calibre = {
    web = {
      enable = mkOption {
        description = "Whether to enable calibre web";
        type = types.bool;
        default = false;
      };

      address = mkOption {
        type = types.str;
        description = "Calibre-web address";
        default = "127.0.0.1";
      };

      port = mkOption {
        type = types.int;
        description = "Calibre-web port";
        default = 9003;
      };
    };

    server = {
      enable = mkOption {
        description = "Whether to enable calibre server";
        type = types.bool;
        default = false;
      };

      address = mkOption {
        type = types.str;
        description = "Calibre-server address";
        default = "127.0.0.1";
      };

      port = mkOption {
        type = types.int;
        description = "Calibre-server port";
        default = 9004;
      };
    };
  };

  config = mkIf enable (mkMerge [
    {
      users.groups."calibre" = { };

      users.users = {
        calibre = {
          name = "calibre";
          uid = config.ids.uids.calibre-server;
          group = "calibre";
          home = "/var/lib/calibre-server";
          isSystemUser = true;
        };
      };
    }
    (mkIf cfg.web.enable {
      services.calibre-web = {
        enable = true;
        inherit user group;
        listen = {
          ip = cfg.web.address;
          inherit (cfg.web) port;
        };
        dataDir = "calibre-web";
        options = {
          calibreLibrary = libraryDir;
          enableBookUploading = true;
          enableBookConversion = true;
        };
      };

      services.nginx.virtualHosts."proxy".locations = {
        "/calibre-web" = {
          proxyPass = "http://${cfg.web.address}:${builtins.toString cfg.web.port}";
          extraConfig = ''
            proxy_bind $server_addr;
            proxy_set_header        Host            chairlift.wg;
            proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header        X-Scheme        $scheme;
            proxy_set_header        X-Script-Name   /calibre-web;
            client_max_body_size 50M;
          '';
        };
      };
    })
    (mkIf cfg.server.enable {
      systemd.services.calibre-server = {
        description = "Calibre Server";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "calibre";
          Restart = "always";
          ExecStart = ''
            ${pkgs.calibre}/bin/calibre-server ${libraryDir} \
               --listen-on=${cfg.server.address} --port=${builtins.toString cfg.server.port} \
               --enable-local-write \
               --url-prefix=/calibre-server
          '';
        };
        environment = {
          XDG_RUNTIME_DIR = "/var/lib/calibre-server";
        };
      };

      services.nginx.virtualHosts."proxy".locations = {
        "/calibre-server/" = {
          proxyPass = "http://${cfg.server.address}:${builtins.toString cfg.server.port}/";
        };
      };
    })
  ]);
}
