{
  config,
  lib,
  pkgs,
  ...
}:
let
  launcher = pkgs.writers.writePython3Bin "wluma-auto" { flakeIgnore = [ "E501" ]; } (
    builtins.readFile ./wluma_launcher.py
  );
  laptop = config.machineData.systemConfig.laptop.enable or false;
in
{
  config = lib.mkIf (config.jd.graphical.wayland.enable && laptop) {
    # wluma 4.x needs explicit devices. Discover them at runtime and use ALS
    # only, avoiding screen-capture overhead and unnecessary GPU wakeups.
    # Manual brightness adjustments in different lighting train its model.
    services.wluma = {
      enable = true;
      systemd.target = "graphical-session.target";
    };
    systemd.user.services.wluma.Service = {
      ExecStart = lib.mkForce "${launcher}/bin/wluma-auto ${lib.getExe config.services.wluma.package}";
      Restart = lib.mkForce "on-failure";
    };
  };
}
