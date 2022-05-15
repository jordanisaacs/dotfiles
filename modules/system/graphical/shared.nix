{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.graphical;
in {
  options.jd.graphical = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable wayland";
    };
  };
  config = mkIf (cfg.enable) {
    environment.systemPackages = with pkgs; [
      # Graphics
      libva-utils
      vdpauinfo
      glxinfo
    ];

    hardware.opengl = {
      enable = true;
      extraPackages = [
        pkgs.mesa.drivers
      ];
    };

    environment.etc = {
      "profile.local".text = builtins.concatStringsSep "\n" ([
          ''
            # /etc/profile.local: DO NOT EDIT -- this file has been generated automatically.
            if [ -f "$HOME/.profile" ]; then
              . "$HOME/.profile"
            fi
          ''
        ]
        ++ (
          if (cfg.xorg.enable && !config.jd.greetd.enable)
          then [
            ''
              if [ -z "$DISPLAY" ] && [ "''${XDG_VTNR}" -eq 1 ]; then
                exec startx
              fi
            ''
          ]
          else []
        )
        ++ (
          if (cfg.wayland.enable && !config.jd.greetd.enable)
          then [
            ''
              if [ -z "$DISPLAY" ] && [ "''${XDG_VTNR}" -eq 2 ]; then
                exec $HOME/.winitrc
              fi
            ''
          ]
          else []
        ));
    };
  };
}
