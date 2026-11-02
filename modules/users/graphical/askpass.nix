{
  config,
  lib,
  pkgs,
  ...
}:
let
  askpass = lib.getExe pkgs.kdePackages.ksshaskpass;
in
{
  # The Python session entry exports these before UWSM starts. Keep both native
  # helpers available to graphical applications without relying on login shells.
  config = lib.mkIf config.jd.graphical.wayland.enable {
    home.sessionVariables = {
      SSH_ASKPASS = askpass;
      SUDO_ASKPASS = askpass;
    };
  };
}
