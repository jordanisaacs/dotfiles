{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.jd.rsyncNetClient;
  client = import ./lib.nix { inherit lib pkgs cfg; };
  bindingFor =
    name:
    assert lib.assertMsg (builtins.hasAttr name client.bindings)
      "Unknown rsyncNetClient binding ${name}";
    client.bindings.${name};
  backups = lib.filterAttrs (_: backup: backup.enable) cfg.serviceBackups;
  caches = lib.filterAttrs (_: cache: cache.enable) cfg.daemonCaches;
  aliases = lib.mapAttrsToList (_: binding: binding.alias) client.bindings;
  hostOrder = alias: 100 + lib.lists.findFirstIndex (value: value == alias) 0 aliases;
  cacheFor =
    name: cache:
    let
      binding = bindingFor cache.binding;
    in
    assert lib.assertMsg (
      binding.principal.backend == "nix-cache" && binding.device.readOnly
    ) "Nix daemon cache ${name} requires a separately enrolled read-only Nix-cache device";
    assert lib.assertMsg (
      binding.principal.cache.signingPublicKeys != [ ]
    ) "Nix daemon cache ${name} requires declared public signing trust";
    {
      url = "ssh://${binding.principal.name}@${binding.alias}?ssh-key=${lib.escapeURL binding.identityFile}";
      keys = binding.principal.cache.signingPublicKeys;
    };
  configuredCaches = lib.mapAttrs cacheFor caches;
in
{
  imports = [ ./options.nix ];
  options.jd.rsyncNetClient = {
    serviceBackups = mkOption {
      default = { };
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = lib.mkEnableOption "this service backup";
            binding = mkOption {
              type = types.str;
              description = "Restic principal/device binding; use service-owned credentials separate from desktop identities.";
            };
            user = mkOption {
              type = types.str;
              default = "root";
              description = "Local service account running the upstream Restic unit; must be able to read its explicit credential files and source data.";
            };
            paths = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Explicit application data/export paths. No system-wide or whole-home default is selected.";
            };
            command = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Upstream Restic --stdin-from-command argv for an application-consistent export; select this or paths. Do not put secret values in arguments.";
            };
            passwordFile = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Root/service-managed runtime repository password file; no desktop agent/keyring dependency and no Nix-store secret content.";
            };
            exclude = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Native Restic exclude patterns.";
            };
            timerConfig = mkOption {
              type = types.nullOr (types.attrsOf types.anything);
              default = null;
              description = "Native systemd timer settings; null requires manual service start.";
            };
          };
        }
      );
      description = "Service backups implemented through upstream NixOS services.restic. Initialization, retention and database-consistency policy remain explicit.";
    };
    daemonCaches = mkOption {
      default = { };
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = lib.mkEnableOption "this Nix-daemon substituter";
            binding = mkOption {
              type = types.str;
              description = "Separately provisioned read-only cache device with root-readable private identity and host trust. Home Manager aliases/desktop agents cannot authenticate the daemon.";
            };
          };
        }
      );
      description = "Signed static Nix caches read over native SSH store transport. Adds public signing keys and a substituter URI with explicit root credential path; never bypasses signature verification.";
    };
    cacheStoreUrls = mkOption {
      type = types.attrsOf types.str;
      readOnly = true;
      description = "Generated native SSH store URLs for enabled daemon caches; identity paths are references, never secret file contents.";
    };
  };
  config = lib.mkMerge [
    {
      jd.rsyncNetClient.cacheStoreUrls =
        if cfg.enable then lib.mapAttrs (_: cache: cache.url) configuredCaches else { };
    }
    (lib.mkIf cfg.enable {
      assertions =
        lib.mapAttrsToList (name: backup: {
          assertion =
            client.runtimeIdentity backup.passwordFile
            && ((backup.paths != [ ]) != (backup.command != [ ]))
            && lib.all (path: lib.hasPrefix "/" path && !lib.hasInfix "\n" path) backup.paths;
          message = "rsyncNetClient service backup ${name} requires an explicit runtime password and either absolute paths or export command";
        }) backups
        ++ lib.optional (caches != { }) {
          assertion = config.nix.settings.require-sigs or true;
          message = "rsyncNetClient daemon caches require Nix signature verification";
        };
      programs.ssh.hosts = lib.mapAttrs' (
        _: binding:
        lib.nameValuePair binding.alias (binding.sshSettings // { order = hostOrder binding.alias; })
      ) client.bindings;
      services.restic.backups = lib.mapAttrs' (
        name: backup:
        let
          binding = bindingFor backup.binding;
        in
        assert lib.assertMsg (
          binding.principal.backend == "restic"
        ) "Service backup ${name} requires a Restic principal";
        lib.nameValuePair "rsync-net-${name}" {
          repository = "rclone:ignored";
          inherit (backup)
            user
            paths
            command
            passwordFile
            exclude
            timerConfig
            ;
          extraOptions = client.resticOptions binding;
          initialize = false;
          pruneOpts = [ ];
          createWrapper = false;
        }
      ) backups;
      nix.settings = lib.mkIf (caches != { }) {
        substituters = lib.mkAfter (map (cache: cache.url) (lib.attrValues configuredCaches));
        trusted-public-keys = lib.mkAfter (
          lib.unique (lib.concatMap (cache: cache.keys) (lib.attrValues configuredCaches))
        );
      };
    })
  ];
}
