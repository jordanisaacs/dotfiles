{ pkgs
, config
, lib
, ...
}:
with lib; let
  wireguardConf = config.jd.wireguard;

  inList = val: builtins.any (item: val == item);

  # Get the list of tag names from a conf
  getTagNames = peerConf:
    map (tag: tag.name) peerConf.tags;

  # Find the first matching value between two lists
  # For each value in the first list, check if in second
  findFirstInSecond = firstList: secondList:
    findFirst
      (vFirst:
        builtins.any
          (vSecond: vFirst == vSecond)
          secondList)
      (builtins.throw "Didn't find any value of the first list in second")
      firstList;

  # Find the matching peer tag config
  # It loops through the provided tags and returns the first config that matches
  # Throws if there is no matching tag
  getTagConf = hostTags: peerConf:
    let
      # Get the config that matches in order of the provided tags
      tagName =
        findFirstInSecond
          hostTags
          (getTagNames peerConf);

      tagConf =
        findFirst
          (conf: conf.name == tagName)
          (builtins.throw "Missing tag in peer")
          peerConf.tags;
    in
    tagConf;

  # Filter out any peer config that does not intersect
  # tags with the given list of tags
  filterTags = hostTags: filterAttrs
    (_: peerConf: (builtins.any
      (peerTag: inList peerTag.name hostTags)
      peerConf.tags));

  # Build the peer configs
  buildPeers = with lib;
    myConf: peerConfs:
      let
        tags = getTagNames myConf;
      in
      mapAttrsToList
        (_: peerConf: (
          let
            tagConf = getTagConf tags peerConf;
            isDynamic = tagConf.ipAddr == null;
          in
          {
            wireguardPeerConfig =
              {
                PublicKey = peerConf.publicKey;
                AllowedIPs = [ "${peerConf.wgAddrV4}/32" ];
                PersistentKeepalive = 25;
              }
              // optionalAttrs (!isDynamic) {
                Endpoint = "${tagConf.ipAddr}:${builtins.toString peerConf.listenPort}";
              };
          }
        ))
        (filterTags tags peerConfs);

  # Build the wireguard conf
  buildConfig = name:
    let
      myConf = wireguardConf.peers.${name};
      peerConfs = builtins.removeAttrs wireguardConf.peers [ name ];
    in
    {
      environment.systemPackages = [ pkgs.wireguard-tools ];

      age.secrets.wireguard_private_key = {
        file = myConf.privateKeyAge;
        path = myConf.privateKeyPath;
        owner = "root";
        group = "systemd-network";
        mode = "0640";
      };

      jd.wireguard.allAddresses = mapAttrsToList (_: v: v.wgAddrV4) wireguardConf.peers;

      networking = {
        firewall.interfaces =
          let
            # allow wireguard listen port on each system interface
            openWireguard =
              listToAttrs
                (builtins.map
                  (name: {
                    inherit name;
                    value = { allowedUDPPorts = [ myConf.listenPort ]; };
                  })
                  config.jd.networking.allInterfaces);
          in
          openWireguard
          // {
            "${wireguardConf.interface}" = {
              inherit (myConf.firewall) allowedUDPPorts;
              inherit (myConf.firewall) allowedTCPPorts;
            };
          };
      };

      systemd.network = {
        networks."99-${wireguardConf.interface}" = {
          matchConfig.Name = wireguardConf.interface;
          routes = [
            {
              routeConfig = {
                PreferredSource = "${myConf.wgAddrV4}";
                Scope = "link";
                Destination = "${myConf.wgAddrV4}/${builtins.toString myConf.interfaceMask}";
              };
            }
          ];
          networkConfig =
            {
              Address = [ "${myConf.wgAddrV4}/32" ];
            }
            // optionalAttrs (myConf.dns == "client") {
              DNS =
                builtins.filter
                  (v: !(builtins.isNull v))
                  (mapAttrsToList
                    (_: peerConf:
                      if (peerConf.dns == "server")
                      then peerConf.wgAddrV4
                      else null)
                    peerConfs);
              Domains = "~.";
              # DNSSEC = true;
              DNSSECNegativeTrustAnchors = mapAttrsToList (_: peerConf: peerConf.domainName) peerConfs;
            };
        };

        netdevs."99-${wireguardConf.interface}" = {
          netdevConfig = {
            Name = wireguardConf.interface;
            Kind = "wireguard";
          };

          wireguardConfig = {
            PrivateKeyFile = myConf.privateKeyPath;
            ListenPort = myConf.listenPort;
          };

          wireguardPeers = buildPeers myConf peerConfs;
        };
      };
    };

  peerTagConf = {
    options = {
      name = mkOption {
        example = "humans";
        type = types.str;
        description = "The name of the tag";
      };

      ipAddr = mkOption {
        type = with types; nullOr str;
        default = null;
        description = ''
          The public ip address of the host broadcasted to network.

          If provided, treated as a server. Otherwise treated as a client.
        '';
      };
    };
  };

  wgConf = { name, ... }: {
    options = {
      publicKey = mkOption {
        example = "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=";
        type = types.str;
        description = "The base64 public key of the host";
      };

      privateKeyPath = mkOption {
        type = types.str;
        description = "The path of where to symlink the decrypted age key";
      };

      privateKeyAge = mkOption {
        type = types.path;
        description = "The age encrypted private key file";
      };

      wgAddrV4 = mkOption {
        example = "10.0.0.1";
        type = types.str;
        description = "The wireguard ipv4 address of the host";
      };

      interfaceMask = mkOption {
        example = 32;
        default = 24;
        type = types.int;
        description = "The /xx netmask for the interface";
      };

      listenPort = mkOption {
        type = types.int;
        description = "The port the host will listen on";
      };

      # TODO: Automatically detect after switch to global config
      dns = mkOption {
        type = types.enum [ "server" "client" "disabled" ];
        description = "Whether this wireguard interface has a dns server, should be a client of the dns servers, or nothing";
        default = "disabled";
      };

      domainName = mkOption {
        type = types.str;
        description = "The private domain name of this peer (used by unbound).";
        default = "${name}.wg";
      };

      firewall = {
        allowedTCPPorts = mkOption {
          type = with types; listOf int;
          default = [ ];
        };

        allowedUDPPorts = mkOption {
          type = with types; listOf int;
          default = [ ];
        };
      };

      tags = mkOption {
        type = with types; listOf (submodule peerTagConf);
        description = ''
          The tags of the peer lists this host belongs to

          The order of the list is the priority in which to apply a tag config (first to last)
        '';
      };
    };
  };
in
{
  options.jd.wireguard = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable wireguard";
    };

    interface = mkOption {
      type = types.str;
      default = "wireguard";
      description = "The name of the wireguard interface";
    };

    peers = mkOption {
      type = with types; attrsOf (submodule wgConf);
      description = "The wireguard configuration for the system";
    };

    allAddresses = mkOption {
      type = with types; listOf str;
      internal = true;
      description = "All addresses on the network";
    };
  };

  config = mkIf wireguardConf.enable (buildConfig config.networking.hostName);
}
