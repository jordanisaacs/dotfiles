{ pkgs
, config
, lib
, ...
}:
with lib;
with builtins; let
  cfg = config.jd.core;
  persist = config.jd.impermanence;
in
{
  options.jd.core = {
    enable = mkOption {
      description = "Enable some core configurations";
      type = types.bool;
      default = true;
    };
  };

  config = mkIf cfg.enable (mkMerge [
    (mkIf persist.enable {
      home.persistence.${persist.backupPool} = [
        "${config.xdg.userDirs.documents}/dev"
        config.xdg.configHome
      ];

      home.persistence.${persist.persistPool} = [
        config.xdg.cacheHome
        ".thunderbird"
      ];
    })
    {
      xdg.enable = true;
      xdg.userDirs.enable = true;
      xdg.mime.enable = true;
      xdg.mimeApps.enable = true;

      home.packages = with pkgs; [ home-manager ];
    }
  ]);
}
