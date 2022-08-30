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
  };

  config = mkIf (config.jd.applications && cfg.enable) {
    programs.taskwarrior = {
      enable = true;
      extraConfig = ''
        taskd.server=10.55.0.2
        taskd.port=53589
      '';
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
