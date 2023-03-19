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
  in
    mkMerge [
      {
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
              (cfg.interfaces ++ lib.optional cfg.wifi.enable cfg.wifi.interface));
        };
      })
      (mkIf cfg.chairlift {
        networking = {
          interfaces.enp1s0.ipv6.addresses = [
            {
              address = "2a01:4ff:f0:865b::1";
              prefixLength = 64;
            }
          ];
          defaultGateway6 = {
            address = "fe80::1";
            interface = "enp1s0";
          };
        };
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
