{ pkgs, config, lib, ... }:

with lib;

let
  inList = val: list: builtins.any (item: val == item) list;

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
  filterTags = hostTags: peerConfs:
    filterAttrs
      (_: peerConf:
        (builtins.any
          (peerTag: inList peerTag.name hostTags)
          peerConf.tags))
      peerConfs;

  # Build the peer configs
  buildPeers = with lib; myConf: peerConfs:
    let
      tags = getTagNames myConf;
    in
    mapAttrsToList
      (_: peerConf: (
        let
          tagConf = getTagConf tags peerConf;
          isStatic = tagConf.ipAddr != null;
        in
        {
          publicKey = peerConf.publicKey;
          allowedIPs = [ "${peerConf.wgAddrV4}/32" ];
          persistentKeepalive = mkIf (!isStatic) 25;
          endpoint = mkIf (isStatic) "${tagConf.ipAddr}:${builtins.toString peerConf.listenPort}";
        }
      ))
      (filterTags tags peerConfs);


  # Build the wireguard conf
  buildConfig = name: wireguardConf:
    let
      myConf = wireguardConf.peers."${name}";
      peerConfs = builtins.removeAttrs wireguardConf.peers [ name ];
    in
    {
      networking = {
        nat = {
          enable = true;
          externalInterface = "eth0";
          internalInterfaces = [ wireguardConf.interface ];
        };

        firewall.interfaces =
          let
            # allow wireguard listen port on each system interface
            openWireguard =
              listToAttrs
                (builtins.map
                  (name: {
                    inherit name; value = { allowedUDPPorts = [ myConf.listenPort ]; };
                  })
                  config.jd.networking.interfaces);
          in
          openWireguard // {
            "${wireguardConf.interface}" = {
              allowedUDPPorts = myConf.firewall.allowedUDPPorts;
              allowedTCPPorts = myConf.firewall.allowedTCPPorts;
            };
          };

        wireguard =
          {
            enable = true;

            interfaces."${wireguardConf.interface}" = {
              ips = [ "${myConf.wgAddrV4}/${builtins.toString myConf.interfaceMask}" ];
              listenPort = myConf.listenPort;
              postSetup = myConf.postSetup;
              postShutdown = myConf.postShutdown;
              privateKeyFile = myConf.privateKeyFile;

              peers = buildPeers myConf peerConfs;
            };
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

  wgConf = ({ name, ... }: {
    options = {
      publicKey = mkOption {
        example = "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=";
        type = types.str;
        description = "The base64 public key of the host";
      };

      privateKeyFile = mkOption {
        type = types.str;
        description = "The path to the private key file of the host";
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

      postSetup = mkOption {
        default = "";
        type = types.str;
        description = "";
      };

      postShutdown = mkOption {
        default = "";
        type = types.str;
        description = "";
      };

      tags = mkOption {
        type = with types; listOf (submodule peerTagConf);
        description = ''
          The tags of the peer lists this host belongs to

          The order of the list is the priority in which to apply a tag config (first to last)
        '';
      };
    };
  });

  cfg = config.jd.wireguard;
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
      description = "The name of the wireguard interface";
    };

    peers = mkOption {
      type = with types; attrsOf (submodule wgConf);
      description = "The wireguard configuration for the system";
    };
  };

  config = mkIf (cfg.enable) (buildConfig (config.networking.hostName) cfg);
}

