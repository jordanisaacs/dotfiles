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
  in {
    networking.interfaces = networkCfg;
    networking.networkmanager.enable = cfg.networkmanager.enable;
    networking.wireless.enable = cfg.wifi.enable;

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
  };
}
