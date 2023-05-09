{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.applications.taskwarrior;
in {
  options.jd.applications.taskwarrior = {
    enable = mkOption {
      description = "Enable taskwarrior";
      type = types.bool;
      default = false;
    };

    server = {
      enable = mkOption {
        description = "Enable connection to taskserver";
        type = types.bool;
        default = false;
      };

      port = mkOption {
        description = "Server port";
        type = types.int;
        default = 53589;
      };

      address = mkOption {
        description = "Server address";
        type = types.str;
        default = "chairlift.wg";
      };

      cert = mkOption {
        description = "The encrypted public cert file";
        type = types.path;
      };

      key = mkOption {
        description = "The encrypted private key file";
        type = types.path;
      };

      ca = mkOption {
        description = "The encrypted ca cert file";
        type = types.path;
      };

      credentials = mkOption {
        description = "Credentials for user";
        type = types.str;
      };
    };
  };

  config = let
    path = config.programs.taskwarrior.dataLocation;
  in
    mkIf (config.jd.applications.enable && cfg.enable)
    {
      programs.taskwarrior = {
        enable = true;
        config = {
          taskd =
            mkIf (cfg.server.enable)
            {
              server = "${cfg.server.address}:${builtins.toString cfg.server.port}";
              key = "${path}/key";
              ca = "${path}/ca";
              certificate = "${path}/cert";
              credentials = "${cfg.server.credentials}";
              trust = "strict";
            };
        };
      };

      homeage.file = mkIf (cfg.server.enable) {
        taskserver-ca = {
          source = cfg.server.ca;
          symlinks = ["${path}/ca"];
        };

        taskserver-key = {
          source = cfg.server.key;
          symlinks = ["${path}/key"];
        };

        taskserver-cert = {
          source = cfg.server.cert;
          symlinks = ["${path}/cert"];
        };
      };
    };
}
# Taskwarrior + timewarrior integration: https://timewarrior.net/docs/taskwarrior/
# home.activation = {
#   tasktime = lib.hm.dag.entryAfter ["writeBoundary"] ''
#     $DRY_RUN_CMD mkdir -p ${config.xdg.dataHome}/task/hooks/
#     $DRY_RUN_CMD rm -rf ${config.xdg.dataHome}/task/hooks/on-modify.timewarrior
#     $DRY_RUN_CMD cp ${pkgs.timewarrior}/share/doc/timew/ext/on-modify.timewarrior ${config.xdg.dataHome}/task/hooks/
#     PYTHON3="#!${pkgs.python3}/bin/python3"
#     $DRY_RUN_CMD ${pkgs.gnused}/bin/sed -i "1s@.*@$PYTHON3@" ${config.xdg.dataHome}/task/hooks/on-modify.timewarrior
#     $DRY_RUN_CMD chmod +x ${config.xdg.dataHome}/task/hooks/on-modify.timewarrior
#   '';
# };

