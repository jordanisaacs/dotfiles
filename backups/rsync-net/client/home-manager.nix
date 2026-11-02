{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Source-local keys placed under xdg.stateHome inherit this repository's
  # existing impermanence persistence. Other runtime paths remain the explicit
  # secret provider's responsibility; activation never copies private keys.
  inherit (lib) mkOption types;
  cfg = config.jd.rsyncNetClient;
  client = import ./lib.nix { inherit lib pkgs cfg; };
  bindingFor =
    name:
    assert lib.assertMsg (builtins.hasAttr name client.bindings)
      "Unknown rsyncNetClient binding ${name}";
    client.bindings.${name};
  backups = lib.filterAttrs (_: backup: backup.enable) cfg.backups;
  gitBindings = lib.filterAttrs (_: binding: binding.principal.backend == "git") client.bindings;
  controller = import ../default.nix {
    inherit pkgs;
    modules = cfg.policyModules;
  };
  identityDescriptor = pkgs.writeText "rsync-net-git-identity.json" (
    builtins.toJSON {
      schemaVersion = 1;
      inherit (cfg.gitIdentity)
        device
        home
        userId
        lookupCommand
        storeCommand
        ;
      inherit (client) manifest;
      bindings = lib.mapAttrs (name: binding: {
        principal = binding.principal.name;
        device = cfg.bindings.${name}.device;
      }) gitBindings;
    }
  );
  machineGpg = pkgs.writeShellScript "rsync-net-machine-gpg" ''
    exec ${controller.cli}/bin/rsync-net-gpg --config ${identityDescriptor} "$@"
  '';
  pathsFor =
    backup: lib.unique (backup.paths ++ map (name: config.xdg.userDirs.${name}) backup.xdgDirectories);
in
{
  imports = [ ./options.nix ];
  options.jd.rsyncNetClient = {
    gitIdentity = {
      enable = lib.mkEnableOption "a keyring-backed per-machine software GPG identity with independent hardware recovery";
      device = mkOption {
        type = types.strMatching "[a-z][a-z0-9_-]{0,30}";
        default = "machine";
      };
      home = mkOption {
        type = types.str;
        default = "${config.xdg.stateHome}/rsync-net/git-gpg/${cfg.gitIdentity.device}";
        description = "Private runtime machine GPG home outside Git/Nix; created only by rsync-net git setup.";
      };
      userId = mkOption {
        type = types.str;
        default = "rsync-net machine ${cfg.gitIdentity.device}";
      };
      publishParticipants = mkOption {
        type = types.bool;
        default = true;
        description = "Use named OpenPGP recipient key IDs. Required for reliable independent ECDH machine/recovery decryption with GnuPG 2.4; repository contents remain encrypted.";
      };
      lookupCommand = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Native keyring argv returning the machine GPG passphrase; public lookup references only.";
      };
      storeCommand = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Native keyring argv accepting a generated passphrase on stdin during setup.";
      };
    };
    backups = mkOption {
      default = { };
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = lib.mkEnableOption "this user backup";
            binding = mkOption {
              type = types.str;
              description = "Restic device binding to use.";
            };
            paths = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Additional user data paths; never defaults to the whole home directory.";
            };
            xdgDirectories = mkOption {
              type = types.listOf (
                types.enum [
                  "desktop"
                  "documents"
                  "download"
                  "music"
                  "pictures"
                  "publicShare"
                  "templates"
                  "videos"
                ]
              );
              default = [
                "documents"
                "pictures"
              ];
              description = "User data directories resolved through upstream xdg.userDirs; select [] when paths are fully explicit.";
            };
            passwordFile = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Runtime repository-password file, outside Nix/Git; select exactly one password source.";
            };
            passwordCommand = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Explicit existing credential-provider command returning the password; no secret content. No keyring policy is invented.";
            };
            exclude = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Upstream Restic exclude patterns.";
            };
            timerConfig = mkOption {
              type = types.nullOr (types.attrsOf types.anything);
              default = null;
              description = "Upstream systemd timer settings; null creates only a manually started backup service.";
            };
            createWrapper = mkOption {
              type = types.bool;
              default = false;
              description = "Install upstream restic-rsync-net-<job> for explicit initialization, inspection and restore using this job's settings.";
            };
          };
        }
      );
      description = "Selected user backups using upstream Home Manager services.restic. Repository initialization and pruning are separate administrative operations.";
    };
    publicKeyFiles = mkOption {
      type = types.attrsOf types.str;
      readOnly = true;
      description = "Declaratively managed public device-key references usable by rsync-net enroll --public-key. Private identities are never copied.";
    };
  };
  config = lib.mkMerge [
    {
      jd.rsyncNetClient.publicKeyFiles =
        if cfg.enable then
          lib.mapAttrs (name: _: "${config.xdg.configHome}/rsync-net/public-keys/${name}.pub") client.bindings
        else
          { };
    }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion =
            !cfg.gitIdentity.enable
            || (
              gitBindings != { }
              && client.runtimeIdentity cfg.gitIdentity.home
              && cfg.gitIdentity.lookupCommand != [ ]
              && cfg.gitIdentity.storeCommand != [ ]
              && lib.all (name: cfg.bindings.${name}.device == cfg.gitIdentity.device) (lib.attrNames gitBindings)
            );
          message = "rsyncNetClient gitIdentity requires this machine's Git bindings, a runtime GPG home and explicit keyring commands";
        }
      ]
      ++ lib.mapAttrsToList (name: backup: {
        assertion =
          (backup.passwordFile == null) != (backup.passwordCommand == null)
          && (backup.passwordFile == null || client.runtimeIdentity backup.passwordFile)
          && pathsFor backup != [ ]
          && lib.all (path: path != null && lib.hasPrefix "/" path) (pathsFor backup);
        message = "rsyncNetClient backup ${name} requires explicit runtime password access and selected absolute data paths";
      }) backups;
      programs = {
        ssh = {
          enable = true;
          enableDefaultConfig = lib.mkDefault false;
          settings = lib.mapAttrs' (
            _: binding: lib.nameValuePair binding.alias binding.sshSettings
          ) client.bindings;
        };
        git = {
          enable = lib.mkIf (gitBindings != { }) true;
          includes = lib.mapAttrsToList (
            name: binding:
            assert lib.assertMsg (
              binding.device.gpgFingerprint != null
            ) "Git host ${name} needs this machine's enrolled GPG identity";
            {
              condition = "hasconfig:remote.*.url:gcrypt::rsync://${binding.principal.name}@${binding.alias}/**";
              contents = {
                gcrypt = {
                  participants = lib.concatStringsSep " " binding.effective.gcryptParticipants;
                  require-explicit-force-push = true;
                  publish-participants = cfg.gitIdentity.publishParticipants;
                };
                user.signingKey = binding.device.gpgFingerprint;
              }
              // lib.optionalAttrs cfg.gitIdentity.enable {
                gpg.program = toString machineGpg;
                gpg.format = "openpgp";
              };
            }
          ) gitBindings;
        };
      };
      xdg.configFile =
        lib.mapAttrs' (
          name: binding:
          lib.nameValuePair "rsync-net/public-keys/${name}.pub" { text = binding.device.publicKey + "\n"; }
        ) client.bindings
        // lib.mapAttrs' (
          name: backup:
          let
            binding = bindingFor backup.binding;
          in
          lib.nameValuePair "rsync-net/backups/${name}.json" {
            text = builtins.toJSON {
              schemaVersion = 1;
              inherit (client) manifest;
              principal = binding.principal.name;
              repository = "rclone:ignored";
              resticOptions = client.resticArgumentOptions binding;
              inherit (backup) passwordFile passwordCommand;
              paths = pathsFor backup;
              recoveryBundle = "${config.xdg.stateHome}/rsync-net/recovery/${binding.principal.name}";
            };
          }
        ) backups
        // lib.optionalAttrs cfg.gitIdentity.enable {
          "rsync-net/git-identity.json".source = identityDescriptor;
        };
      services.restic.enable = lib.mkIf (backups != { }) true;
      services.restic.backups = lib.mapAttrs' (
        name: backup:
        let
          binding = bindingFor backup.binding;
        in
        assert lib.assertMsg (
          binding.principal.backend == "restic"
        ) "User backup ${name} needs a Restic principal";
        lib.nameValuePair "rsync-net-${name}" {
          repository = "rclone:ignored";
          inherit (backup)
            passwordFile
            passwordCommand
            exclude
            timerConfig
            createWrapper
            ;
          paths = pathsFor backup;
          extraOptions = client.resticOptions binding;
          initialize = false;
          pruneOpts = [ ];
        }
      ) backups;
      home.packages =
        lib.optionals (gitBindings != { }) [
          pkgs.git-remote-gcrypt
          pkgs.rsync
        ]
        ++ lib.optionals cfg.gitIdentity.enable [ controller.cli ];
    })
  ];
}
