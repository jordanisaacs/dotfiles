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
          value = {useDHCP = false;};
        })
        cfg.interfaces);
  in
    mkMerge [
      (mkIf cfg.wifi.enable {
        jd.networking.interfaces = ["wlan0"];
        networking.wireless.iwd = {
          enable = true;
          settings = {
            General = {
              EnableNetworkConfiguration = true;
              UseDefaultInterface = false;
            };
            Network = {
              NameResolvingService = "systemd";
              EnableIPv6 = true;
            };
          };
        };
      })
      {
        networking = {
          interfaces = networkCfg;
          useNetworkd = true;
          useDHCP = false;
          enableIPv6 = true;
        };

        networking.firewall = mkIf (cfg.firewall.enable) {
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
              cfg.interfaces);
        };
      }
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
        networking.resolvconf.enable = false;

        services.resolved = {
          # https://blogs.gnome.org/mcatanzaro/2020/12/17/understanding-systemd-resolved-split-dns-and-vpn-configuration/
          enable = true;
          fallbackDns = [
            # Quad9
            "9.9.9.9"
            "149.112.112.112"
            "2620:fe::fe"
            "2620:fe::9"
          ];
        };

        # https://zwischenzugs.com/2018/06/08/anatomy-of-a-linux-dns-lookup-part-i/
        system.nssDatabases.hosts = [
          "mymachines"
          "resolve"
          "[!UNAVAIL=return]"
          "files"
          "myhostname"
          "mdns4_minimal"
          "[!NOTFOUND=return]"
          "dns"
        ];
      })
    ];
}
