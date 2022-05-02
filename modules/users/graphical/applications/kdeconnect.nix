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

  portsOpen = let cfg = config.machineData.systemConfig.networking.firewall; in (!cfg.enable || cfg.allowKdeconnect);
in {
  options.jd.graphical.applications.kdeconnect = {
    enable = mkOption {
      default = false;
      type = types.bool;
      description = "Enable libreoffice with config [libreoffice]";
    };
  };

  config =
    mkIf
    (isGraphical && cfg.enable && cfg.kdeconnect.enable && (assertMsg portsOpen "need to open ports on host"))
    {
      services.kdeconnect = {
        enable = true;
        indicator = true;
      };
    };
}
