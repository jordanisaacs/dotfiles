{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.jd.desktop;
in
{
  options.jd.desktop = {
    enable = mkOption {
      description = "Whether to enable desktop settings. Also tags as desktop for user settings";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (cfg.enable) {
    networking =
      let
        wireguardName = "thevoid";
      in
      {
        nat.enable = true;
        nat.externalInterface = "eth0";
        nat.internalInterfaces = [ wireguardName ];

        firewall = {
          allowedUDPPorts = [ 51820 ];
          interfaces.${wireguardName}.allowedTCPPorts = [ 8080 ];
        };



        wireguard = {
          enable = true;
          interfaces = {
            thevoid = {
              ips = [ "10.55.0.1/16" ];
              listenPort = 51820;

              privateKeyFile = "/keys/wireguard/private";

              postSetup = ''
                ${pkgs.iptables}/bin/iptables -A FORWARD -i thevoid -o thevoid -j ACCEPT
              '';

              postShutdown = ''
                ${pkgs.iptables}/bin/iptables -D FORWARD -i thevoid -o thevoid -j ACCEPT
              '';

              peers = [
                {
                  # phone
                  publicKey = "alkGf4EOzctjDL67HQxo/kGYuBGe+1S/2Rk0xcg+Dzs=";
                  allowedIPs = [ "10.55.1.1/32" ];
                }
                {
                  # laptop
                  publicKey = "ruxqBTX1+ReVUwQY3u5qwJIcm6d/ZnUJddP9OewNqjI=";
                  allowedIPs = [ "10.55.1.2/32" ];
                }
              ];
            };
          };
        };
      };
  };
}
