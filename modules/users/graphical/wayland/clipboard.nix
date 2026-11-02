{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.jd.graphical.wayland;
  pythonScript = import ../../../../lib/python-script.nix { inherit pkgs; };
  python = pkgs.python3.withPackages (packages: [ packages.pygobject3 ]);
  vaultSettings = {
    cipherDirectory = "${config.xdg.stateHome}/clipboard-history/vault";
    gocryptfs = lib.getExe' pkgs.gocryptfs "gocryptfs";
    systemctl = "${pkgs.systemd}/bin/systemctl";
    notify = "${pkgs.systemd}/bin/systemd-notify";
    fusermount = "/run/wrappers/bin/fusermount3";
  };
  vaultSource = pkgs.writeText "clipboard-vault.py" (
    ''
      #!${python}/bin/python3
      import json
      CONFIG = json.loads(${builtins.toJSON (builtins.toJSON vaultSettings)})

    ''
    + builtins.readFile ../../../../scripts/clipboard-vault.py
  );
  vault = pkgs.stdenvNoCC.mkDerivation {
    pname = "clipboard-vault";
    version = "1";
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.wrapGAppsNoGuiHook
      pkgs.gobject-introspection
    ];
    buildInputs = [ pkgs.libsecret ];
    installPhase = ''
      install -Dm755 ${vaultSource} "$out/bin/clipboard-vault"
    '';
  };
  database =
    if cfg.clipboard.persistent then "%t/clipboard-history/plain/db" else "%t/clipboard-history/db";
  picker = pythonScript "clipboard-history" ../../../../scripts/clipboard.py {
    cliphist = lib.getExe config.services.cliphist.package;
    fuzzel = lib.getExe pkgs.fuzzel;
    wlCopy = "${pkgs.wl-clipboard}/bin/wl-copy";
    persistent = cfg.clipboard.persistent;
    vault = "${vault}/bin/clipboard-vault";
  };
  watcher = {
    Unit =
      if cfg.clipboard.persistent then
        {
          Requires = [ "clipboard-vault.service" ];
          BindsTo = [ "clipboard-vault.service" ];
          After = [ "clipboard-vault.service" ];
          ConditionPathIsMountPoint = "%t/clipboard-history/plain";
        }
      else
        {
          Requires = [ "clipboard-session.service" ];
          After = [ "clipboard-session.service" ];
        };
    Service = {
      Environment = [ "CLIPHIST_DB_PATH=${database}" ];
      UMask = "0077";
      LimitCORE = 0;
      Slice = "background-graphical.slice";
    };
  };
in
{
  options.jd.graphical.wayland.clipboard = {
    persistent = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Retain keyring-encrypted clipboard history between graphical logins; disabling uses only session-owned runtime storage.";
    };
    vaultPackage = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
      default = vault;
      description = "Keyring-unlocked native encrypted clipboard vault lifecycle.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
      default = picker;
      description = "Clipboard history picker and deletion controls.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.cliphist = {
      enable = true;
      allowImages = true;
      systemdTargets = [ "graphical-session.target" ];
    };
    systemd.user.services = {
      cliphist = watcher;
      cliphist-images = watcher;
      clipboard-vault = lib.mkIf cfg.clipboard.persistent {
        Unit = {
          Description = "Encrypted clipboard history unlocked by the login keyring";
          PartOf = [ "graphical-session.target" ];
          After = [
            "graphical-session.target"
            "gnome-keyring.service"
          ];
          Before = [
            "cliphist.service"
            "cliphist-images.service"
          ];
        };
        Service = {
          Type = "notify";
          NotifyAccess = "all";
          KillMode = "mixed";
          ExecCondition = "${vault}/bin/clipboard-vault check";
          ExecStart = "${vault}/bin/clipboard-vault serve";
          RuntimeDirectory = "clipboard-history";
          RuntimeDirectoryMode = "0700";
          UMask = "0077";
          LimitCORE = 0;
          TimeoutStartSec = 40;
          TimeoutStopSec = 15;
          Slice = "background-graphical.slice";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
      clipboard-session = lib.mkIf (!cfg.clipboard.persistent) {
        Unit = {
          Description = "Clipboard history for the active graphical session";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
          Before = [
            "cliphist.service"
            "cliphist-images.service"
          ];
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
          RuntimeDirectory = "clipboard-history";
          RuntimeDirectoryMode = "0700";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
    home.packages = [ picker ] ++ lib.optional cfg.clipboard.persistent vault;
    xdg.desktopEntries = {
      clipboard-history = {
        name = "Clipboard History";
        genericName = "Search and copy saved clipboard entries";
        exec = "${picker}/bin/clipboard-history pick";
        icon = "edit-paste";
        terminal = false;
        categories = [ "Utility" ];
      };
      clipboard-history-delete = {
        name = "Delete Clipboard Entry";
        genericName = "Remove a saved clipboard entry";
        exec = "${picker}/bin/clipboard-history delete";
        icon = "edit-delete";
        terminal = false;
        categories = [ "Utility" ];
      };
      clipboard-history-clear = {
        name = "Clear Clipboard History";
        genericName = "Delete saved clipboard entries after confirmation";
        exec = "${picker}/bin/clipboard-history clear";
        icon = "edit-clear-history";
        terminal = false;
        categories = [ "Utility" ];
      };
    };
  };
}
