{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.jd.proxy;
in {
  # TODO: incomplete
  options.jd.proxy = {
    enable = mkOption {
      description = "Whether to enable nginx reverse proxy";
      type = types.bool;
      default = false;
    };

    firewall = mkOption {
      type = types.enum ["world" "wg" "closed"];
      default = "closed";
      description = "What level firewall to open";
    };

    address = mkOption {
      type = types.str;
      description = "Proxy address";
      default = "127.0.0.1";
    };

    port = mkOption {
      type = types.int;
      description = "Proxy port";
      default = 80;
    };
  };

  config = mkIf (cfg.enable) (mkMerge [
    {
      services.roundcube = {
        enable = true;
        hostName = "roundcube";
        extraConfig = ''
          $config['smtp_server'] = "tls//${config.mailserver.fqdn}";
          $config['smtp_user'] = "%u";
          $config['smtp_pass'] = "%p";
        '';
        dicts = with pkgs.aspellDicts; [en];
      };
    }
    (mkIf (cfg.firewall == "world") {
      networking.firewall.allowedTCPPorts = [cfg.port];
    })
    (
      let
        wgconf = config.jd.wireguard;
      in
        mkIf
        (cfg.firewall == "wg" && (assertMsg wgconf.enable "Wireguard must be enabled for wireguard ssh firewall"))
        {
          networking.firewall.interfaces.${wgconf.interface}.allowedTCPPorts = [cfg.port];
        }
    )
  ]);
}
