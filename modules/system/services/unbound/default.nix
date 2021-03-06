{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.jd.unbound;
in {
  options.jd.unbound = {
    enable = mkOption {
      description = "Whether to enable unbound";
      type = types.bool;
      default = false;
    };

    access = mkOption {
      type = types.enum ["world" "wg" "closed"];
      default = "closed";
      description = "What level access to DNS";
    };

    enableWGDomain = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable custom wireguard domains. e.g. access 10.55.0.1 from example.wg. Domains set in wireguard settings";
    };
  };

  config = let
    unboundPort = config.services.unbound.settings.server.port;
    wgIps = config.networking.wireguard.interfaces.${config.jd.wireguard.interface}.ips;
    wgIpsStripped = with builtins;
      map
      (ip: head (splitString "/" ip))
      wgIps;
    wgIpsAccess =
      builtins.map
      (ip: "${ip} allow")
      wgIps;

    peerConfs = config.jd.wireguard.peers;
    peerZone =
      attrsets.mapAttrsToList
      (_: v: ''"${v.domainName}" redirect'')
      peerConfs;
    peerData =
      attrsets.mapAttrsToList
      (_: v: ''"${v.domainName} IN A ${v.wgAddrV4}"'')
      peerConfs;
    peerPtrs =
      attrsets.mapAttrsToList
      (_: v: ''"${v.wgAddrV4} www.${v.domainName}"'')
      peerConfs;
  in
    mkIf (cfg.enable) (mkMerge [
      {
        services.unbound = let
        in {
          enable = true;
          resolveLocalQueries = true;
          settings = {
            server = {
              port = 53;
              so-reuseport = "yes";
              # use all CPUs
              num-threads = 2;

              # power of 2 close to num-threads
              msg-cache-slabs = 4;
              rrset-cache-slabs = 4;
              infra-cache-slabs = 4;
              key-cache-slabs = 4;

              # more cache memory, rrset=msg*2
              msg-cache-size = "50m";
              rrset-cache-size = "100m";

              # NixOS compiles with libevent
              outgoing-range = 8192;
              num-queries-per-thread = 4096;

              module-config = ''"validator iterator"'';

              hide-identity = "yes";
              hide-trustanchor = "yes";
              harden-glue = "yes";
              harden-dnssec-stripped = "yes";
              harden-below-nxdomain = "yes";
              use-caps-for-id = "yes";
              qname-minimisation = "yes";
              qname-minimisation-strict = "no";
              unwanted-reply-threshold = 10000;

              cache-min-ttl = 3600;
              cache-max-ttl = 86400;
              prefetch = "yes";

              interface =
                if (cfg.access == "world")
                then ["0.0.0.0"]
                else
                  ["127.0.0.0"]
                  ++ (optionals
                    (cfg.access == "wg")
                    wgIpsStripped);
              do-ip4 = "yes";
              do-ip6 = "yes";
              do-udp = "yes";
              do-tcp = "yes";
              access-control =
                if (cfg.access == "world")
                then ["0.0.0.0/0 allow"]
                else
                  ["127.0.0.0/8 allow"]
                  ++ (optionals
                    (cfg.access == "wg")
                    wgIpsAccess);
              local-zone = mkIf (cfg.enableWGDomain) peerZone;
              local-data = mkIf (cfg.enableWGDomain) peerData;
              local-data-ptr = mkIf (cfg.enableWGDomain) peerPtrs;
              private-address = ["10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "169.254.0.0/16" "fd00::/8" "fe80::/10"];
              root-hints = builtins.fetchurl {
                url = "https://www.internic.net/domain/named.cache";
                sha256 = "12knv0yy6p7v38xd74j226b0l6inq438zl8l5661k45rg1mjiqvi";
              };
            };
          };
        };
      }
      (mkIf (cfg.access == "world") {
        networking.firewall = {
          allowedTCPPorts = [unboundPort];
          allowedUDPPorts = [unboundPort];
        };
      })
      (
        let
          wgconf = config.jd.wireguard;
        in
          mkIf
          (cfg.access == "wg" && (assertMsg wgconf.enable "Wireguard must be enabled for wireguard ssh firewall"))
          {
            networking.firewall.interfaces.${wgconf.interface} = {
              allowedTCPPorts = [unboundPort];
              allowedUDPPorts = [unboundPort];
            };
          }
      )
    ]);
}
