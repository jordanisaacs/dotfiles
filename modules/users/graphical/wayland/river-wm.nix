{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.jd.graphical.wayland;
  pythonScript = import ../../../../lib/python-script.nix { inherit pkgs; };
  switcher = pythonScript "river-wm" ../../../../scripts/river-wm.py {
    systemctl = "${pkgs.systemd}/bin/systemctl";
  };
  stopReka = pythonScript "reka-stop" ../../../../scripts/reka-stop.py {
    emacsclient = "${config.programs.emacs.finalPackage}/bin/emacsclient";
    alternateEditor = "${pkgs.coreutils}/bin/false";
  };
  managerUnit = name: command: {
    Unit = {
      Description = "${name} window manager for the active River session";
      PartOf = [ "graphical-session.target" ];
      Conflicts = [ "river-wm-${if name == "reka" then "oxbow" else "reka"}.service" ];
    };
    Service = {
      Type = "notify";
      NotifyAccess = "all";
      ExecStart = command;
      ExecStopPost = "${pkgs.systemd}/bin/systemctl --user unset-environment OXBOW_SOCKET JD_RIVER_WM";
      Environment = [ "JD_RIVER_WM=${name}" ];
      Slice = "session.slice";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStartSec = 30;
      TimeoutStopSec = 10;
    };
  };
in
{
  options.jd.graphical.wayland.river.switchPackage = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    internal = true;
    default = switcher;
    description = "Runtime selector for the managed River window managers.";
  };

  config = lib.mkIf (cfg.enable && cfg.type == "river") {
    home.packages = [ switcher ];
    # Stop the dynamic controller before UWSM terminates River. An After edge
    # to River would deadlock startup while River awaits controller readiness.
    xdg.configFile."systemd/user/wayland-wm@river.service.d/50-window-managers.conf".text = ''
      [Service]
      ExecStop=${pkgs.systemd}/bin/systemctl --user stop river-wm-reka.service river-wm-oxbow.service
    '';
    systemd.user.services = {
      river-wm-oxbow = managerUnit "oxbow" "${pkgs.oxbow}/bin/oxbow";
      river-wm-reka =
        lib.recursiveUpdate
          (managerUnit "reka" "${config.programs.emacs.finalPackage}/bin/emacs -Q --load ${lib.escapeShellArg "${config.xdg.configHome}/reka/init.el"}")
          {
            # Queue normal Lisp shutdown at a safe boundary, then wait for
            # the main process: server cleanup disconnects emacsclient early.
            Service.ExecStop = "${stopReka}/bin/reka-stop";
            Unit = {
              # One ordering edge also makes direct systemctl starts wait for
              # the conflicting manager to finish stopping, in either direction.
              After = [ "river-wm-oxbow.service" ];
              Wants = [ "river-input.service" ];
            };
          };
    };
  };
}
