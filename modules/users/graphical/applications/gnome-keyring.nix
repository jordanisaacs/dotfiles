{ pkgs, config, lib, ... }:
with lib;
let cfg = config.jd.graphical;
in {
  options.jd.graphical.applications.gnome-keyring = {
    enable = mkEnableOption "gnome-keyring";
    enableSSH = mkEnableOption "ssh support";
  };

  config = mkIf ((cfg.xorg.enable || cfg.wayland.enable)
    && cfg.applications.gnome-keyring.enable) {
      home = {
        sessionVariables = mkIf cfg.applications.gnome-keyring.enableSSH {
          SSH_AUTH_SOCK = "\${XDG_RUNTIME_DIR}/keyring/ssh";
          SSH_ASKPASS = "${pkgs.seahorse}/libexec/seahorse/ssh-askpass";
        };

        packages = [ pkgs.seahorse ];
      };

      systemd.user.services.gnome-keyring =
        throwIfNot config.machineData.systemConfig.gnome.keyring.enable
        "Gnome Keyring must be enabled on system as well." {
          Unit = {
            Description = "GNOME Keyring";
            PartOf = [ "graphical-session-pre.target" ];
          };

          Service = {
            ExecStart =
              "/run/wrappers/bin/gnome-keyring-daemon --start --foreground";
            Restart = "on-abort";
          };

          Install = { WantedBy = [ "graphical-session-pre.target" ]; };
        };
    };
}
