{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.jd.microbin;

  name = "microbin";
  user = name;
  group = name;
  id = 327;
in {
  options.jd.microbin = {
    enable = mkOption {
      description = "Whether to enable microbin";
      type = types.bool;
      default = false;
    };

    address = mkOption {
      type = types.str;
      description = "Microbin address";
      default = "127.0.0.1";
    };

    port = mkOption {
      type = types.int;
      description = "Microbin port";
      default = 9001;
    };
  };

  config = mkIf (cfg.enable) (mkMerge [
    (mkIf config.jd.impermanence.enable {
      environment.persistence.${config.jd.impermanence.persistedDatasets."data".backup} = {
        directories = ["/var/lib/private/microbin"];
      };
    })
    {
      systemd.services.microbin = {
        description = "Microbin - pastebin server";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];

        serviceConfig = {
          ExecStart = ''
            ${pkgs.microbin}/bin/microbin \
              --editable --hide-footer --highlightsyntax \
              --wide --qr --gc-days 0 \
              --enable-burn-after \
              -b ${cfg.address} -p ${builtins.toString cfg.port} \
              --public-path="http://chairlift.wg/microbin"
          '';
          DynamicUser = true;
          StateDirectory = "microbin";
          WorkingDirectory = "/var/lib/microbin";
          ProtectProc = "invisible";
          Type = "simple";
          Restart = "always";
        };
      };
    }
  ]);
}
