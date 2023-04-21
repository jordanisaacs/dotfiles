{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.networking;
in {
  options.jd.networking = {
    interfaces = mkOption {
      type = with types; listOf str;
      default = [];
      description = "List of network interface cards, do not add wifi card";
    };

    allInterfaces = mkOption {
      internal = true;
      default = [];
      description = "List of network interface cards";
    };

    wifi = {
      enable = mkOption {
        description = "Enable wifi with default options";
        type = types.bool;
        default = false;
      };

      interface = mkOption {
        type = types.str;
        default = "wlan0";
        description = "Name of wifi NIC";
      };
    };

    static = {
      enable = mkOption {
        description = "Enable static addresses";
        type = types.bool;
        default = false;
      };

      interface = mkOption {
        description = "Name of NIC";
        default = null;
        type = types.str;
      };

      ipv4 = {
        gateway = mkOption {
          description = "ipv4 gateway";
          type = types.str;
          default = null;
        };

        onlink = mkOption {
          description = "Whether the gateway is not on the same network as the address";
          type = types.bool;
          default = false;
        };

        addr = mkOption {
          description = "ipv4 address";
          type = types.str;
          default = null;
        };
      };

      ipv6 = {
        addr = mkOption {
          description = "ipv6 address";
          type = types.str;
          default = null;
        };
      };
    };

    chairlift = mkOption {
      description = "Enable chairlift networking.";
      type = types.bool;
      default = false;
    };

    firewall = {
      enable = mkOption {
        description = "Enable firewall";
        type = types.bool;
        default = false;
      };

      allowKdeconnect = mkOption {
        description = "Open ports in firewall to allow KDE connect";
        type = types.bool;
        default = false;
      };

      allowDefaultSyncthing = mkOption {
        description = "Open ports in firewall to allow syncthing";
        type = types.bool;
        default = false;
      };
    };
  };

  config = let
    networkCfg =
      listToAttrs
      (map
        (n: {
          name = "${n}";
          # Use builtin DHCP of iwd
          value = {useDHCP = true;};
        })
        cfg.interfaces);

    interfaces =
      cfg.interfaces
      ++ lib.optional cfg.wifi.enable cfg.wifi.interface
      ++ lib.optional cfg.static.enable cfg.static.interface;
  in
    mkMerge [
      {
        jd.networking.allInterfaces = interfaces;
        networking = {
          # TODO: Switch to systemd-networkd
          # Routing
          # http://linux-ip.net/html/basic-reading.html
          interfaces = networkCfg;
          useNetworkd = true;
          useDHCP = false;
          enableIPv6 = true;
        };
      }
      (mkIf cfg.wifi.enable {
        systemd.network.networks."40-${cfg.wifi.interface}" = {
          matchConfig = {
            Name = "${cfg.wifi.interface}";
          };
          networkConfig = {
            DHCP = "yes";
            # https://wiki.archlinux.org/title/IPv6#Privacy_extensions
            IPv6PrivacyExtensions = "kernel";
          };
        };

        # Race condition with where iwd starts before wireless network card powers on
        # https://wiki.archlinux.org/title/Iwd#Restarting_iwd.service_after_boot
        systemd.services.iwd.serviceConfig.ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";

        networking.wireless.iwd = {
          enable = true;
          settings = {
            General = {
              # EnableNetworkConfiguration = true;
              UseDefaultInterface = false;
            };
            Network = {
              NameResolvingService = "systemd";
              EnableIPv6 = true;
            };
          };
        };
      })
      (mkIf cfg.firewall.enable {
        # Use nftables
        networking.nftables.enable = true;
        networking.firewall = {
          enable = true;
          interfaces =
            listToAttrs
            (map
              (n: {
                name = n;
                value = mkMerge [
                  (mkIf cfg.firewall.allowKdeconnect rec {
                    allowedTCPPortRanges = [
                      {
                        from = 1714;
                        to = 1764;
                      }
                    ];
                    allowedUDPPortRanges = allowedTCPPortRanges;
                  })
                  (mkIf cfg.firewall.allowDefaultSyncthing {
                    allowedTCPPorts = [2200];
                    allowedUDPPorts = [21027 22000];
                  })
                ];
              })
              interfaces);
        };
      })
      (mkIf cfg.static.enable {
        systemd.network.networks."40-${cfg.static.interface}" = {
          matchConfig = {
            Name = cfg.static.interface;
          };

          networkConfig = {
            Address = [cfg.static.ipv4.addr cfg.static.ipv6.addr];
            DNS = ["9.9.9.9" "149.112.112.112" "2620:fe::fe" "2620:fe::9"]; # quad9
            DNSSEC = "allow-downgrade";
            # https://tldp.org/HOWTO/Linux+IPv6-HOWTO/ch06s05.html
            IPv6PrivacyExtensions = "no";
            # IPv6AcceptRA = true;
            # LinkLocalAddressing = "ipv6";
          };

          routes = [
            {routeConfig.Gateway = "fe80::1";}
            {
              routeConfig = {
                Gateway = cfg.static.ipv4.gateway;
                GatewayOnLink = cfg.static.ipv4.onlink;
              };
            }
            # {
            #   routeConfig = {
            #     Gateway = "0.0.0.0";
            #     Destination = cfg.static.ipv4.gateway;
            #   };
            # }
          ];
        };

        # hack around to set up our networking. not "post" but just give it ordering before all
        # other postCommands
        boot.initrd.network.postCommands = mkBefore ''
          echo "Bringing up ${cfg.static.interface}"
          ip link set ${cfg.static.interface} up
          echo "Setting address and routes"
          ip addr add ${cfg.static.ipv4.addr} dev ${cfg.static.interface} scope global
          ip route add ${cfg.static.ipv4.gateway} dev ${cfg.static.interface} scope link
          ip route add default via ${cfg.static.ipv4.gateway} dev ${cfg.static.interface}
        '';
      })
      # If unbound is enabled do not use systemd-resolved
      (mkIf (!config.jd.unbound.enable) {
        # https://zwischenzugs.com/2018/06/08/anatomy-of-a-linux-dns-lookup-part-i/
        # https://blogs.gnome.org/mcatanzaro/2020/12/17/understanding-systemd-resolved-split-dns-and-vpn-configuration/
        networking.resolvconf.enable = false;

        services.resolved = {
          enable = true;
          fallbackDns = [
            # Quad9
            "9.9.9.9"
            "149.112.112.112"
            "2620:fe::fe"
            "2620:fe::9"
          ];
        };

        system.nssDatabases.hosts = mkForce [
          # Resolution for containers registered with systemd-machined
          # see man nss-mymachines
          "mymachines"
          # Use systemd-resolved
          # see man nss-systemd
          "resolve"
          # if systemd-resolved was available, return immediately
          "[!UNAVAIL=return]"
          # Check /etc/hosts to see if hardcoded
          "files"
          # Local hostname is always resolveable
          "myhostname"
          # Avahi for mdns resolution
          "mdns4_minimal"
          # If "no such name found" then return immediately
          "[NOTFOUND=return]"
          # Check /etc/resolve.conf for DNS
          "dns"
        ];
      })
    ];
}
