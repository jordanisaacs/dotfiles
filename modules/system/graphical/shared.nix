{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.graphical;
in
{
  options.jd.graphical = {
    enable = mkEnableOption "graphical desktop support";

    flatpak.enable = mkEnableOption "flatpak application support";
  };
  config = mkIf cfg.enable (mkMerge [
    {
      environment.systemPackages = with pkgs; [
        # Graphics
        libva-utils
        vdpauinfo
        glxinfo
      ];

      hardware.opengl = {
        enable = true;
        extraPackages = with pkgs; [
          mesa.drivers
        ];
      };

      environment.etc = {
        "profile.local".text = builtins.concatStringsSep "\n" (
          [
            ''
              # /etc/profile.local: DO NOT EDIT -- this file has been generated automatically.
              if [ -f "$HOME/.profile" ]; then
                . "$HOME/.profile"
              fi
            ''
          ]
          ++ lib.optional (cfg.xorg.enable && !config.jd.greetd.enable)
            ''
              if [ -z "$DISPLAY" ] && [ "''${XDG_VTNR}" -eq 1 ]; then
                exec startx
              fi
            ''
          ++ lib.optional (cfg.wayland.enable && !config.jd.greetd.enable)
            ''
              if [ -z "$DISPLAY" ] && [ "''${XDG_VTNR}" -eq 2 ]; then
                exec $HOME/.winitrc
              fi
            ''
        );
      };
    }
    (mkIf cfg.flatpak.enable {
      services.flatpak.enable = true;
    })
    (mkIf config.jd.networking.wifi.enable {
      programs.captive-browser = {
        enable = true;
        bindInterface = true;
        inherit (config.jd.networking.wifi) interface;
      };
    })
  ]);
}
