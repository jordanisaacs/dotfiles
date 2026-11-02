{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.jd.graphical.wayland;
  python = pkgs.python3.withPackages (packages: [ packages.pygobject3 ]);
  rekaBridge = pkgs.writeText "reka-logout.el" (builtins.readFile ../../../../scripts/logout-reka.el);
  settings = {
    applicationId = "dev.snowytrees.DesktopLogout";
    systemctl = "${pkgs.systemd}/bin/systemctl";
    oxctl = "${pkgs.oxbow}/bin/oxctl";
    emacsclient = "${config.programs.emacs.finalPackage}/bin/emacsclient";
    uwsm = "${pkgs.uwsm}/bin/uwsm";
    health =
      if cfg.logout.healthPackage == null then
        null
      else
        lib.getExe' cfg.logout.healthPackage "river-health";
  };
  source = pkgs.writeText "desktop-logout.py" (
    ''
      #!${python}/bin/python3
      import json
      CONFIG = json.loads(${builtins.toJSON (builtins.toJSON settings)})

    ''
    + builtins.readFile ../../../../scripts/desktop-logout.py
  );
  package = pkgs.stdenvNoCC.mkDerivation {
    pname = "desktop-logout";
    version = "1";
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.wrapGAppsHook3
      pkgs.gobject-introspection
    ];
    buildInputs = [ pkgs.gtk3 ];
    installPhase = ''
      install -Dm755 ${source} "$out/bin/desktop-logout"
    '';
    meta.mainProgram = "desktop-logout";
  };
in
{
  options.jd.graphical.wayland.logout.healthPackage = lib.mkOption {
    type = lib.types.nullOr lib.types.package;
    default = null;
    description = "Optional native River response observer; absent support uses Waiting for app.";
  };

  options.jd.graphical.wayland.logout.package = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    internal = true;
    default = package;
    description = "Shared graphical logout confirmation and application-close monitor.";
  };

  config = lib.mkIf (cfg.enable && cfg.type == "river") {
    home.packages = [ package ];
    xdg.desktopEntries.${settings.applicationId} = {
      name = "Log Out";
      genericName = "Close applications and end the desktop session";
      exec = "${package}/bin/desktop-logout";
      icon = "system-log-out";
      terminal = false;
      categories = [ "System" ];
    };
    xdg.configFile."reka/init.el".text = lib.mkAfter ''
      (load ${builtins.toJSON (toString rekaBridge)} nil t)
    '';
  };
}
