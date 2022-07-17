{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.jd.miniflux;
in {
  options.jd.miniflux = {
    enable = mkOption {
      description = "Whether to enable miniflux";
      type = types.bool;
      default = false;
    };

    adminCredsFile = mkOption {
      type = types.path;
      description = "The age encrypted credentials file";
    };

    decryptCredsPath = mkOption {
      type = types.path;
      description = "Where to decrypt credentials file";
      default = "/etc/miniflux/admin-credentials";
    };

    firewall = mkOption {
      type = types.enum ["world" "wg" "closed"];
      default = "closed";
      description = "Open firewall to everyone or wireguard";
    };

    address = mkOption {
      type = types.str;
      description = "Miniflux address";
      default = "127.0.0.1";
    };

    port = mkOption {
      type = types.int;
      description = "Miniflux port";
      default = 8080;
    };
  };

  config = mkIf (cfg.enable) (mkMerge [
    {
      services = {
        miniflux = {
          enable = true;
          adminCredentialsFile = cfg.decryptCredsPath;
          config = {
            LISTEN_ADDR = "${cfg.address}:${builtins.toString cfg.port}";
            CLEANUP_ARCHIVE_UNREAD_DAYS = "-1";
            CLEANUP_ARCHIVE_READ_DAYS = "-1";
            FETCH_YOUTUBE_WATCH_TIME = "1";
            # metrics_collector = 1;
            LOG_DATE_TIME = "on";
            BASE_URL = let
              proxy = config.jd.proxy;
            in
  mkIf (proxy.enable) "http://${proxy.address}:${builtins.toString proxy.port}/miniflux/";
          };
        };
      };

      age.secrets.miniflux_admin_creds = {
        file = cfg.adminCredsFile;
        path = cfg.decryptCredsPath;
        mode = "600";
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
