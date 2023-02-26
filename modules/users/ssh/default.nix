{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.ssh;
in {
  options.jd.ssh = {
    enable = mkOption {
      description = "enable ssh";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    programs.ssh = {
      enable = true;
      matchBlocks = {
        localhost = {
          hostname = "127.0.0.1";
          user = "root";
          identityFile = "~/.ssh/local";
        };
      };
      extraConfig = ''
        AddKeysToAgent yes
      '';
    };
  };
}
