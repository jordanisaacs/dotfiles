{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.jd.ssh;
in
{
  options.jd.ssh = {
    enable = mkOption {
      description = "Whether to enable laptop settings. Also tags as laptop for user settings";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (cfg.enable) {
    programs.ssh.startAgent = true;
  };
}
