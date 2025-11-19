{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
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
      useTextGreeter = true;
      settings = {
        terminal.vt = 1;
        default_session =
          let
            waylandSession = pkgs.writeTextFile {
              name = "wayland-session.desktop";
              destination = "/wayland-session.desktop";
              text = ''
                [Desktop Entry]
                Name=Wayland
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
                if (config.jd.graphical.enable && config.jd.graphical.wayland.enable) then
                  [ waylandSession ]
                else
                  [ ]
              )
              ++ [ zshSession ]
              ++ (
                if (config.jd.graphical.enable && config.jd.graphical.xorg.enable) then [ xorgSession ] else [ ]
              )
            );
          in
          {
            command = "${pkgs.tuigreet}/bin/tuigreet --time --sessions ${sessionDirs} --remember --remember-user-session";
            user = "greeter";
          };
      };
    };
  };
}
