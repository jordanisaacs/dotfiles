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
    {
      users = {
        groups.${group} = {};
        users.${user} = {
          inherit group;
          isSystemUser = true;
          description = "Microbin user";
        };
      };

      systemd.services.microbin = let
        microbin = pkgs.rustPlatform.buildRustPackage rec {
          pname = "microbin";
          version = "1.2.0";

          src = pkgs.fetchCrate {
            inherit pname version;
            sha256 = "sha256-dZClslUTUchx+sOJzFG8wiAgyW/0RcCKfKYklKfVrzM=";
          };

          cargoSha256 = "sha256-fBbChu5iy/2H/8IYCwd1OwxplGPZAmkd8z8xD7Uc0vo=";
        };
      in {
        description = "Microbin - pastebin server";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];

        serviceConfig = {
          ExecStart = ''
            ${microbin}/bin/microbin \
              --editable --hide-footer --highlightsyntax \
              --wide --qr --gc-days 0 \
              --enable-burn-after \
              -b ${cfg.address} -p ${builtins.toString cfg.port} \
              --public-path="http://chairlift.wg/microbin"
          '';
          Type = "simple";
          User = user;
          Group = group;
          WorkingDirectory = "/var/lib/microbin";
          Restart = "always";
        };
      };
    }
  ]);
}
