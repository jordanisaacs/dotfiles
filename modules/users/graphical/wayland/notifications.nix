{
  config,
  lib,
  ...
}:
let
  cfg = config.jd.graphical.wayland;
  package = config.services.swaync.package;
  client = "${package}/bin/swaync-client";
  uiPixels = config.gtk.font.size * 4 / 3;
in
{
  config = lib.mkIf cfg.enable {
    services.swaync = {
      enable = true;
      settings = {
        positionX = "right";
        positionY = cfg.statusbar.position;
        control-center-layer = "overlay";
        notification-grouping = true;
        widgets = [
          "title"
          "dnd"
          "notifications"
        ];
        widget-config = {
          title = {
            text = "Notifications";
            clear-all-button = true;
            button-text = "Clear All";
          };
          dnd.text = "Do Not Disturb";
          notifications.vexpand = true;
        };
      };
      style = ''
        :root {
          --cc-bg: rgb(25, 32, 42);
          --noti-bg: 25, 32, 42;
          --noti-bg-alpha: 1;
          --font-size-body: ${toString uiPixels}px;
          --font-size-summary: ${toString uiPixels}px;
        }
        * {
          font-family: "${config.gtk.font.name}";
          font-size: ${toString config.gtk.font.size}pt;
        }
      '';
    };
    # Keep a package/global D-Bus activation file from restarting a second
    # notification daemon after this user's native service takes ownership.
    xdg.configFile."systemd/user/mako.service".source = config.lib.file.mkOutOfStoreSymlink "/dev/null";
    systemd.user.services.swaync = {
      Unit.Conflicts = [ "mako.service" ];
      Service.Slice = "background-graphical.slice";
    };
    xdg.desktopEntries.notification-center = {
      name = "Notification Center";
      genericName = "Notification history and Do Not Disturb";
      exec = "${client} --toggle-panel --skip-wait";
      icon = "preferences-system-notifications";
      terminal = false;
      categories = [
        "Settings"
        "DesktopSettings"
      ];
    };
  };
}
