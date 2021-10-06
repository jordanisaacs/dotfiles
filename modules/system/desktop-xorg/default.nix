{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.jd.xserver;
in
{
  options.jd.xserver = {
    enable = mkOption {
      description = "Enable xserver.";
      type = types.bool;
      default = false;
    };

    display-manager = {
      type = mkOption {
        description = "Display-manager type. Options: startx";
        type = types.enum [ "startx" ];
        default = null;
      };
    };
  };

  config = mkIf (cfg.enable) {
    services.xserver = {
      enable = true;
      libinput = {
        enable = true;
        touchpad = {
          naturalScrolling = true;
        };
      };

      displayManager.startx.enable = (cfg.display-manager.type == "startx");
    };

    environment.etc = mkIf (cfg.display-manager.type == "startx") {
      "profile.local".text = ''
        # /etc/profile.local: DO NOT EDIT -- this file has been generated automatically.
        if [ -f "$HOME/.profile" ]; then
          . "$HOME/.profile"
        fi

        if [ -z "$DISPLAY" ] && [ "''${XDG_VTNR}" -eq 1 ]; then
          exec startx
        fi

        if [ -z "$DISPLAY" ] && [ "''${XDG_VTNR}" -eq 2 ]; then
          exec $HOME/.winitrc
        fi
      '';
    };
  };
}
