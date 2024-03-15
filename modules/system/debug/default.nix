{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.debug;
in
{
  options.jd.debug = {
    enable = mkEnableOption "debug tools";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ gdb strace elfutils bpftrace ];
  };
}
