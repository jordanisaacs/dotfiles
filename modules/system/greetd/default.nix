{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.greetd;
in
{
  options.jd.greetd.enable = mkOption {
    description = "Enable greetd";
    default = false;
    type = types.bool;
  };

  config = mkIf cfg.enable {
    services.greetd = {
      enable = true;
      restart = true;
      settings = {
        terminal.vt = 1;
        default_session =
          let
            swaySession = pkgs.writeTextFile {
              name = "sway-session.desktop";
              destination = "/sway-session.desktop";
              text = ''
                [Desktop Entry]
                Name=Sway
                Exec=$HOME/.winitrc
              '';
            };

            zshSession = pkgs.writeTextFile {
              name = "zsh-session.desktop";
              destination = "/zsh-session.desktop";
              text = ''
                [Desktop Entry]
                Name=Terminal
                Exec=${pkgs.zsh}/bin/zsh
              '';
            };

            xorgSession = pkgs.writeTextFile {
              name = "xorg-session.desktop";
              destination = "/xorg-session.desktop";
              text = ''
                [Desktop Entry]
                Name=X11
                Exec=${pkgs.xlibs.xinit}/bin/startx
              '';
            };

            # First session is used by default
            sessionDirs = builtins.concatStringsSep ":" (
              (
                if (config.jd.graphical.enable && config.jd.graphical.wayland.enable)
                then [ swaySession ]
                else [ ]
              )
              ++ [ zshSession ]
              ++ (
                if (config.jd.graphical.enable && config.jd.graphical.xorg.enable)
                then [ xorgSession ]
                else [ ]
              )
            );
          in
          {
            command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --sessions ${sessionDirs} --remember --remember-user-session";
            user = "greeter";
          };
      };
    };
  };
}
