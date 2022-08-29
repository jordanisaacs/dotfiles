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
      description = "List of network interface cards";
    };

    networkmanager.enable = mkOption {
      description = "Enable network manager with default options";
      type = types.bool;
      default = false;
    };

    wifi.enable = mkOption {
      description = "Enable wifi with default options";
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
    };
  };

  config = let
    networkCfg =
      listToAttrs
      (map
        (n: {
          name = "${n}";
          value = {useDHCP = true;};
        })
        cfg.interfaces);
  in
    mkMerge [
      {
        networking = {
          interfaces = networkCfg;
          networkmanager.enable = cfg.networkmanager.enable;
          wireless = mkIf (cfg.wifi.enable) {
            enable = true;
          };
        };

        networking.firewall = mkIf (cfg.firewall.enable) {
          enable = true;
          interfaces =
            mkIf
            (cfg.firewall.allowKdeconnect)
            (listToAttrs
              (map
                (n: {
                  name = n;
                  value = rec {
                    allowedTCPPortRanges = [
                      {
                        from = 1714;
                        to = 1764;
                      }
                    ];
                    allowedUDPPortRanges = allowedTCPPortRanges;
                  };
                })
                cfg.interfaces));
        };
      }
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
