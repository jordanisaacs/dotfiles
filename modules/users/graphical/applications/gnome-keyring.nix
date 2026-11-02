{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.graphical;
in
{
  options.jd.graphical.applications.gnome-keyring = {
    enable = mkEnableOption "gnome-keyring";
    enableSSH = mkEnableOption "ssh support";
  };

  config = mkIf (cfg.wayland.enable && cfg.applications.gnome-keyring.enable) {
    home = {
      sessionVariables = mkIf cfg.applications.gnome-keyring.enableSSH {
        SSH_AUTH_SOCK = "\${XDG_RUNTIME_DIR}/keyring/ssh";
        SSH_ASKPASS = "${pkgs.seahorse}/libexec/seahorse/ssh-askpass";
      };

      packages = [ pkgs.seahorse ];
    };

    assertions = [
      {
        assertion = config.machineData.systemConfig.gnome.keyring.enable;
        message = "GNOME Keyring must be enabled on the system as well.";
      }
    ];
  };
}
