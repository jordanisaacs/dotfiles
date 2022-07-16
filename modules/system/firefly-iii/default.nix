{
  config,
  lib,
  pkgs,
  ...
}:
# TODO: Incomplete
with lib; let
  cfg = config.jd.firefly-iii;
in {
  options.jd.firefly-iii = {
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

  config = {
    services = {
      nginx = {
        enable = true;
        virtualHosts."firefly.com" = {
          enableACME = true;
          forceSSL = true;
          root = pkgs.jdpkgs.firefly-iii;
          locations."~ \.php$".extraConfig = ''
            fastcgi_pass unix:${config.services.phpfpm.pools.firefly.socket};
            fastcgi_index index.php;
          '';
        };
      };

      phpfpm.pools.firefly = {
        user = "firefly";
        settings = {
          "listen.owner" = config.services.nginx.user;
          "pm" = "dynamic";
          "pm.max_children" = 5;
          "pm.start_servers" = 1;
          "pm.min_spare_servers" = 1;
          "pm.max_spare_servers" = 3;
          "pm.max_requests" = 500;
        };
      };
    };
  };
}
