{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.jd.graphical.inputRemapping;
  defaults = import ../../../lib/mac-shortcuts.nix;
  applications = lib.unique (
    cfg.applications ++ lib.concatMap (entry: entry.applications) cfg.applicationShortcuts
  );
  policy = (pkgs.formats.yaml { }).generate "desktop-command-shortcuts.yaml" {
    enable_wheel = false;
    modmap = lib.optional cfg.capsLockAsAlt {
      name = "Preserve Caps as Option in remapped applications";
      application.only = applications;
      remap.CapsLock = "KEY_LEFTALT";
    };
    keymap = [
      {
        name = "Application Command shortcuts";
        exact_match = true;
        application.only = cfg.applications;
        remap = cfg.shortcuts;
      }
    ]
    ++ map (entry: {
      inherit (entry) name;
      exact_match = true;
      application.only = entry.applications;
      remap = entry.shortcuts;
    }) cfg.applicationShortcuts;
  };
  uid = name: toString config.users.users.${name}.uid;
in
{
  options.jd.graphical.inputRemapping = {
    enable = lib.mkEnableOption "session-scoped application Command shortcuts";
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Accounts allowed to provide graphical application context to the dedicated input service.";
    };
    capsLockAsAlt = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Mirror the desktop XKB Caps-to-Alt choice in positive application contexts before shortcut matching.";
    };
    applications = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[^\n]+");
      default = defaults.applications;
      description = "Positive xremap application identities using standard Control accelerators; exclude terminals and GTK Emacs editors.";
    };
    applicationShortcuts = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            applications = lib.mkOption { type = lib.types.listOf (lib.types.strMatching "[^\n]+"); };
            shortcuts = lib.mkOption { type = lib.types.attrsOf lib.types.str; };
          };
        }
      );
      default = defaults.applicationShortcuts;
      description = "Additional disjoint application shortcut policies, each scoped to positive app identities.";
    };
    shortcuts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = defaults.shortcuts;
      description = "Exact Command combinations translated inside the explicitly supported GUI applications.";
    };
    package = lib.mkPackageOption pkgs "xremap" { };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package.sessionGuarded or false;
        message = "Desktop input remapping requires xremap's active unlocked graphical-session and focus-state guards.";
      }
      {
        assertion = cfg.users != [ ];
        message = "Input remapping requires an explicit list of allowed user accounts.";
      }
      {
        assertion = lib.all (
          name:
          builtins.hasAttr name config.users.users
          && config.users.users.${name}.isNormalUser
          && config.users.users.${name}.uid != null
        ) cfg.users;
        message = "Input remapping users must be normal accounts with explicit UIDs.";
      }
      {
        assertion = applications != [ ] && lib.all (name: name != "" && name != "/.*/") applications;
        message = "Input remapping must use positive application identities, never an unrestricted match.";
      }
    ];
    hardware.uinput.enable = true;
    users.groups = {
      xremap = { };
    }
    // lib.genAttrs (map (name: "xremap-${name}") cfg.users) (_: { });
    users.users = {
      xremap = {
        isSystemUser = true;
        group = "xremap";
        extraGroups = [
          "input"
          "uinput"
        ]
        ++ map (name: "xremap-${name}") cfg.users;
      };
    }
    // lib.genAttrs cfg.users (name: {
      extraGroups = [ "xremap-${name}" ];
    });
    systemd.tmpfiles.rules = [
      # A pre-existing logind uaccess ACL can retain group::--- while udev's
      # MODE=0660 changes only its mask. Restore the declared owning group's
      # access without removing the active user's existing ACL entry.
      "a+ /dev/uinput - - - - g::rw"
      "d /run/xremap 0755 xremap xremap -"
    ]
    ++ map (name: "d /run/xremap/${uid name} 2770 xremap xremap-${name} -") cfg.users;
    systemd.services.desktop-input = {
      description = "Session-scoped desktop Command shortcut translation";
      documentation = [
        "https://github.com/xremap/xremap/blob/v0.15.15/doc/running_as_system_service.md"
      ];
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      serviceConfig = {
        Type = "simple";
        User = "xremap";
        Group = "xremap";
        ExecStart = lib.escapeShellArgs [
          "${cfg.package}/bin/xremap"
          "--desktop=socket"
          "--watch=device"
          "--no-window-logging"
          "--allow-launch=false"
          policy
        ];
        Restart = "on-failure";
        RestartSec = 1;
        RuntimeDirectory = "xremap";
        RuntimeDirectoryMode = "0755";
        RuntimeDirectoryPreserve = "yes";
        UMask = "0077";
        NoNewPrivileges = true;
        CapabilityBoundingSet = [ ];
        PrivateNetwork = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        SystemCallArchitectures = "native";
        DevicePolicy = "closed";
        DeviceAllow = [
          "char-input rw"
          "/dev/uinput rw"
        ];
      };
    };
  };
}
