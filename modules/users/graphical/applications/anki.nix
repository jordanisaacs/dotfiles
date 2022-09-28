{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.graphical.applications;
  isGraphical = let
    cfg = config.jd.graphical;
  in (cfg.xorg.enable == true || cfg.wayland.enable == true);
in {
  options.jd.graphical.applications.anki = {
    enable = mkOption {
      default = false;
      type = types.bool;
      description = "Enable anki";
    };

    sync = mkOption {
      default = false;
      type = types.bool;
      description = "Enable syncing";
    };

    addr = mkOption {
      default = "http://chairlift.wg:27701/";
      type = types.str;
      description = "Address to sync to";
    };
  };

  config =
    mkIf
    (isGraphical && cfg.enable && cfg.anki.enable)
    {
      home = {
        packages = [pkgs.anki-bin];
        file."${config.xdg.dataHome}/Anki2/addons21/ankisyncd/__init__.py" = mkIf (cfg.anki.sync) {
          text = ''
            import os

            addr = "${cfg.anki.addr}" # put your server address here
            os.environ["SYNC_ENDPOINT"] = addr + "sync/"
            os.environ["SYNC_ENDPOINT_MEDIA"] = addr + "msync/"
          '';
        };
      };
    };
}
