{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.jd.greetd;
  graphical = config.jd.graphical.enable && config.jd.graphical.wayland.enable;
  pythonScript = import ../../../lib/python-script.nix { inherit pkgs; };
  bootstrap = pythonScript "desktop-login" ../../../scripts/desktop-login.py { };
  sessions = pkgs.linkFarm "desktop-login-sessions" (
    # Tuigreet classifies this entire directory as Wayland. A terminal must
    # use its native free-command interface, without graphical PAM metadata.
    lib.optionals graphical (
      map
        (manager: {
          name = "share/wayland-sessions/river-${manager}.desktop";
          path = pkgs.writeText "river-${manager}.desktop" ''
            [Desktop Entry]
            Type=Application
            Name=River (${if manager == "reka" then "Reka" else "Oxbow"})
            Exec=${bootstrap}/bin/desktop-login --window-manager ${manager}
            DesktopNames=river
          '';
        })
        [
          "reka"
          "oxbow"
        ]
    )
  );
  settingsFile = (pkgs.formats.toml { }).generate "desktop-greeter.toml" {
    display.show_time = true;
    session = {
      # Tuigreet sorts session names, so directory order cannot choose a default.
      # The command and environment are passed to the authenticated account.
      command =
        "desktop-login "
        + (if graphical then "--window-manager ${cfg.defaultWindowManager}" else "--terminal");
      environments = [
        "PATH=${bootstrap}/bin:/run/wrappers/bin:/run/current-system/sw/bin"
      ]
      ++ lib.optionals graphical [
        "XDG_SESSION_TYPE=wayland"
        "XDG_CURRENT_DESKTOP=river"
        "XDG_SESSION_DESKTOP=river"
      ];
      sessions_dirs = [ "${sessions}/share/wayland-sessions" ];
    };
    remember = {
      username = true;
      # Remembered sessions override the declaratively selected default.
      session = false;
      user_session = false;
    };
  };
  greeter = pythonScript "login-greeter" ../../../scripts/desktop.py {
    action = "command";
    command = [
      "${pkgs.tuigreet}/bin/tuigreet"
      "--config"
      (toString settingsFile)
    ];
  };
in
{
  imports = [ ./boot-keyring.nix ];
  options.jd.greetd = {
    enable = lib.mkEnableOption "greetd login management";
    defaultWindowManager = lib.mkOption {
      type = lib.types.enum [
        "oxbow"
        "reka"
      ];
      default = "oxbow";
      description = "River window manager preselected at login for all users.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = greeter;
      defaultText = lib.literalExpression "the configured Tuigreet package";
      description = "Login greeter shared by all system users.";
    };
  };

  config = lib.mkIf cfg.enable {
    # greetd starts the account's login shell, whose profile constructs PATH.
    # Keep the short default command available after that initialization too.
    environment.systemPackages = [ bootstrap ];
    services.greetd = {
      enable = true;
      restart = true;
      useTextGreeter = true;
      settings = {
        terminal.vt = 1;
        default_session = {
          command = lib.getExe cfg.package;
          user = "greeter";
        };
      };
    };
  };
}
