{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.networking;
  pythonScript = import ../../../lib/python-script.nix { inherit pkgs; };
  migrateIwd = pythonScript "wifi-migrate-iwd" ./migrate-iwd.py {
    source = "/var/lib/iwd";
    destination = "/etc/wpa_supplicant/imperative.conf";
  };
  ipTime = pythonScript "ip-time" ./ip-time.py {
    interface = cfg.wifi.interface;
    curl = "${pkgs.curl}/bin/curl";
    timedatectl = "${pkgs.systemd}/bin/timedatectl";
  };
  ipTimeRules = pkgs.linkFarm "ip-time-dispatcher-rules" [
    {
      name = "routable.d/ip-time";
      path = "${ipTime}/bin/ip-time";
    }
  ];
in
{
  options.jd.networking = {
    interfaces = mkOption {
      type = with types; listOf str;
      default = [ ];
      description = "List of network interface cards, do not add wifi card";
    };

    allInterfaces = mkOption {
      internal = true;
      default = [ ];
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

      permanentMACAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Permanent adapter MAC used to give the Wi-Fi link its configured name.";
      };

      ipTime = mkEnableOption "set time based on ip when wifi interface routes";
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

    tailscale.enable = mkEnableOption "tailscale";
  };

  config =
    let
      networkCfg = listToAttrs (
        map (n: {
          name = "${n}";
          # systemd-networkd provides DHCP for explicitly configured wired links.
          value = {
            useDHCP = true;
          };
        }) cfg.interfaces
      );

      interfaces =
        cfg.interfaces
        ++ lib.optional cfg.wifi.enable cfg.wifi.interface
        ++ lib.optional cfg.static.enable cfg.static.interface;
    in
    mkMerge [
      {
        jd.networking.allInterfaces = interfaces;
        networking = {
          # Routing
          # http://linux-ip.net/html/basic-reading.html
          interfaces = networkCfg;
          useNetworkd = true;
          useDHCP = false;
          enableIPv6 = true;
        };
      }
      (mkIf cfg.wifi.enable (mkMerge [
        {
          systemd = {
            # Match the adapter, not its kernel or predictable interface name.
            # An early .link takes precedence over systemd's default name policy.
            network.links = mkIf (cfg.wifi.permanentMACAddress != null) {
              "10-wifi" = {
                matchConfig.PermanentMACAddress = cfg.wifi.permanentMACAddress;
                linkConfig = {
                  NamePolicy = "";
                  Name = cfg.wifi.interface;
                };
              };
            };
            network.networks."40-${cfg.wifi.interface}" = {
              matchConfig = {
                Name = "${cfg.wifi.interface}";
              };
              networkConfig = {
                DHCP = "yes";
                IPv6AcceptRA = true;
                # LinkLocalAddressing = "ipv6";
                # https://wiki.archlinux.org/title/IPv6#Privacy_extensions
                IPv6PrivacyExtensions = "kernel";
              };
              # A laptop should boot normally when it is away from a saved AP.
              linkConfig.RequiredForOnline = "no";
            };

            # The upstream module permits group writes to the imperative file.
            # Clients only need its control socket, so keep credentials private.
            services."wpa_supplicant-${cfg.wifi.interface}".serviceConfig.ExecStartPre = mkAfter [
              "+${pkgs.coreutils}/bin/chmod 0600 /etc/wpa_supplicant/imperative.conf"
            ];

            tmpfiles.rules = [
              "d /etc/wpa_supplicant 0750 wpa_supplicant wpa_supplicant -"
            ];

            # Import supported credentials before first startup without putting
            # them in the Nix store. Existing supplicant config and all iwd files
            # are retained; unsupported enterprise profiles need manual setup.
            services.wifi-profile-migration = {
              description = "Import saved iwd Wi-Fi profiles";
              requiredBy = [ "wpa_supplicant-${cfg.wifi.interface}.service" ];
              before = [ "wpa_supplicant-${cfg.wifi.interface}.service" ];
              after = [
                "systemd-sysusers.service"
                "systemd-tmpfiles-setup.service"
              ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${migrateIwd}/bin/wifi-migrate-iwd";
                User = "root";
                UMask = "0077";
                ProtectSystem = "strict";
                ProtectHome = true;
                PrivateTmp = true;
                ReadWritePaths = [ "/etc/wpa_supplicant" ];
                NoNewPrivileges = true;
              };
            };
          };

          networking.wireless = {
            enable = true;
            interfaces = [ cfg.wifi.interface ];
            userControlled = true;
            allowAuxiliaryImperativeNetworks = true;
            dbusControlled = false;
          };
          users.groups.wpa_supplicant.members = map (user: user.name) config.jd.users.users;
          environment.systemPackages = [ migrateIwd ];

        }
        (mkIf cfg.wifi.ipTime {
          assertions = [
            {
              assertion = config.jd.core.time == null;
              message = "Need time set to null for ip time";
            }
          ];

          services.networkd-dispatcher = {
            enable = true;
            # The module's rules option always wraps hooks in a shell.
            # Supply the directly executable Python hook instead.
            extraArgs = mkForce [ "--script-dir=${ipTimeRules}" ];
          };
        })
      ]))
      (mkIf cfg.firewall.enable {
        # Use nftables
        networking.nftables.enable = true;
        networking.firewall = {
          enable = true;
          interfaces = listToAttrs (
            map (n: {
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
                  allowedTCPPorts = [ 2200 ];
                  allowedUDPPorts = [
                    21027
                    22000
                  ];
                })
              ];
            }) interfaces
          );
        };
      })
      (mkIf cfg.static.enable {
        systemd.network.networks."40-${cfg.static.interface}" = {
          matchConfig = {
            Name = cfg.static.interface;
          };

          networkConfig = {
            Address = [
              cfg.static.ipv4.addr
              cfg.static.ipv6.addr
            ];
            DNS = [
              "9.9.9.9"
              "149.112.112.112"
              "2620:fe::fe"
              "2620:fe::9"
            ]; # quad9
            DNSSEC = "allow-downgrade";
            # https://tldp.org/HOWTO/Linux+IPv6-HOWTO/ch06s05.html
            IPv6PrivacyExtensions = "no";
            # IPv6AcceptRA = true;
            # LinkLocalAddressing = "ipv6";
          };

          routes = [
            { routeConfig.Gateway = "fe80::1"; }
            {
              routeConfig = {
                Gateway = cfg.static.ipv4.gateway;
                GatewayOnLink = cfg.static.ipv4.onlink;
              };
            }
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
      (mkIf cfg.tailscale.enable {
        services.tailscale = {
          enable = true;
          useRoutingFeatures = "client";
          disableUpstreamLogging = true;
        };
      })
      # If unbound is enabled do not use systemd-resolved
      (mkIf (!config.jd.unbound.enable) {
        # https://zwischenzugs.com/2018/06/08/anatomy-of-a-linux-dns-lookup-part-i/
        # https://blogs.gnome.org/mcatanzaro/2020/12/17/understanding-systemd-resolved-split-dns-and-vpn-configuration/
        networking.resolvconf.enable = false;

        services.resolved = {
          enable = true;
          settings.Resolve.DNSStubListenerExtra = "[::1]:53";
          settings.Resolve.FallbackDNS = [
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
