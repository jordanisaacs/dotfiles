{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.debug;
in
{
  options.jd.debug = {
    enable = mkEnableOption "debug";
    nixseparatedebuginfod.enable = mkEnableOption "nix separate debug infod";
  };

  config = mkIf cfg.enable (mkMerge [
    {
      environment.systemPackages = with pkgs; [
        gdb
        strace
        elfutils
        bpftrace
      ];
      systemd.coredump.enable = true;
    }
    (mkIf cfg.nixseparatedebuginfod.enable {
      services.nixseparatedebuginfod2.enable = true;
    })
  ]);
}
