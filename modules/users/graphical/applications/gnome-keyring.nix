{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.graphical;
in {
  options.jd.graphical.gnome-keyring = {
    enable = mkEnableOption "gnome-keyring with ssh support";
  };

  config = mkIf (cfg.xorg.enable == true || cfg.wayland.enable == true) {
    home = {
      sessionVariables = {
        SSH_AUTH_SOCK = "\${XDG_RUNTIME_DIR}/keyring/ssh";
        SSH_ASKPASS = "${pkgs.gnome.seahorse}/libexec/seahorse/ssh-askpass";
      };

      packages = with pkgs; [gnome.seahorse];
    };

    systemd.user.services.gnome-keyring =
      throwIfNot
      config.machineData.systemConfig.gnome.keyring.enable
      "Gnome Keyring must be enabled on system as well."
      {
        Unit = {
          Description = "GNOME Keyring";
          PartOf = ["graphical-session-pre.target"];
        };

        Service = {
          ExecStart = "/run/wrappers/bin/gnome-keyring-daemon --start --foreground";
          Restart = "on-abort";
        };

        Install = {WantedBy = ["graphical-session-pre.target"];};
      };
  };
}
