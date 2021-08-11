{ pkgs, lib, config, ... }:
{
  home.packages = with pkgs; [ dwm st ];

  home.file = {
    ".xinitrc" = {
      text = ''
        if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
          eval $(dbus-launch --exit-with-session --sh-syntax)
        fi
        systemctl --user import-environment DISPLAY XAUTHORITY
        
        if command -v dbus-update-activation-environment >/dev/null 2>&1; then
          dbus-update-activation-environment DISPLAY XAUTHORITY
        fi
        
        [ -f ~/.xprofile ] && . ~/.xprofile
        [ -f ~/.Xresources ] && xrdb -merge ~/.Xresources
        
        systemctl --user start graphical-session.target

        exec ${pkgs.dwm}/bin/dwm
     '';
     executable = true;
    };
  };
}
