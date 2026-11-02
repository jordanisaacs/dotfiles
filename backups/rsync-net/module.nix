{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.rsyncNet;
  nullableId = types.nullOr types.ints.positive;
  fingerprint = types.strMatching "([A-F0-9]{40}|[A-F0-9]{64})";
  snapshotSchedules = types.attrsOf (
    types.submodule {
      options = {
        schedule = mkOption {
          type = types.strMatching "[0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+";
          description = "Five-field FreeBSD cron schedule in server local time.";
        };
        retention = mkOption {
          type = types.strMatching "(forever|[1-9][0-9]*[sMhdwmy])";
          description = "Native zfsnap2 lifetime, e.g. 48h, 30d, 12w, 1y, or forever.";
        };
      };
    }
  );
in
{
  options.rsyncNet = {
    snapshotSchedules = mkOption {
      type = snapshotSchedules;
      default = { };
      description = "Shared snapshot schedule defaults for every backup, Git and binary cache dataset. Each dataset may override snapshots, including {} to disable. Applied through rsync-net snapshots configure after separate server prerequisite setup.";
    };
    mode = mkOption {
      type = types.enum [
        "public"
        "private"
      ];
      default = "public";
      description = "Public uses the provider's existing SSH listener and root-managed per-principal home authorization. Private mode is reserved and incomplete; activation is blocked.";
    };
    connection = {
      host = mkOption {
        type = types.str;
        description = "Provider SSH hostname shared by administrative and scoped public-mode service identities.";
      };
      user = mkOption {
        type = types.str;
        default = "root";
        description = "Administrative account used only for inspection and explicitly reviewed reconstruction.";
      };
      port = mkOption {
        type = types.port;
        default = 22;
        description = "Existing provider SSH port; public-mode routine identities use this listener too.";
      };
      interpreter = mkOption {
        type = types.str;
        default = "/usr/local/bin/python3.11";
        description = "Absolute path to an already installed provider Python interpreter; bootstrap installs no packages.";
      };
    };
    setup = {
      snapshotting = lib.mkEnableOption "the native zfsnap2 snapshot/expiry prerequisite";
      backends = mkOption {
        type = types.listOf (
          types.enum [
            "restic"
            "git"
            "nix-cache"
          ]
        );
        default = [ "restic" ];
        description = "Server capabilities whose native packages setup installs, independently of enrolled backup principals.";
      };
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Allow separately reviewed native FreeBSD prerequisite installation; stop/disable only recognized legacy managed inetd while retaining its files. Backup accounts use bootstrap, and ZFS filesystems use storage init. Never upgrades the OS, modifies provider repositories/public SSH, or enrolls Tailscale.";
      };
      expectedRelease = mkOption {
        type = types.nullOr (types.strMatching "[0-9]+\\.[0-9]+-RELEASE(-p[0-9]+)?");
        default = null;
        description = "Explicitly approved freebsd-version -u release; null blocks setup. Reapprove after provider OS replacement.";
      };
    };
    pool = {
      name = mkOption {
        type = types.str;
        default = "data1";
        description = "Existing ZFS pool name; reconstruction verifies identity and never creates or imports a pool.";
      };
      guid = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Verified numeric pool GUID, never inferred from its name.";
      };
    };
    recovery = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Require a public recovery-recipient policy by default for encrypted
          Restic/Git principals. This declares policy only: account bootstrap
          does not provision or verify repository encryption or recovery secrets.
        '';
      };
      recipients = mkOption {
        type = types.listOf fingerprint;
        default = [ ];
        description = ''
          Default full public OpenPGP fingerprints for recovery. Git writers must
          include them in every repository's participant configuration; Restic
          setup must encrypt a separate native recovery password to these keys.
          Recovery password envelopes require separate explicit provisioning;
          this public declaration does not install them on the provider.
          Clients must have matching public certificates; no keyserver lookup is
          implied. Private keys and passwords never belong in this configuration.
        '';
      };
    };
    principals = mkOption {
      default = { };
      type = types.attrsOf (
        types.submodule (
          { name, config, ... }: {
            options = {
              name = mkOption {
                type = types.str;
                default = name;
                description = "Stable OS account name; defaults to the principal attribute name.";
              };
              uid = mkOption {
                type = nullableId;
                default = null;
                description = "Explicit stable nonroot UID; null blocks reconstruction rather than allocating an identity.";
              };
              gid = mkOption {
                type = nullableId;
                default = null;
                description = "Explicit stable primary GID; null blocks reconstruction rather than allocating an identity.";
              };
              home = mkOption {
                type = types.str;
                default = "/home/${name}";
                description = "Root-owned home path restored by bootstrap; not a repository or an authorization database.";
              };
              backend = mkOption {
                type = types.enum [
                  "restic"
                  "git"
                  "nix-cache"
                ];
                description = "Storage backend shared by enrolled devices: Restic append-only backups, encrypted Git hosting, or signed static Nix cache access over SSH. Git writers must serialize updates.";
              };
              dataset = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Declared existing dataset assigned to this principal; bootstrap does not create storage.";
              };
              cache = mkOption {
                type = types.nullOr (
                  types.submodule {
                    options = {
                      signingPublicKeys = mkOption {
                        type = types.listOf types.str;
                        default = [ ];
                        description = "Accepted Nix public signing keys; signing secrets stay on approved builders. Empty trust blocks deployment.";
                      };
                    };
                  }
                );
                default = if config.backend == "nix-cache" then { } else null;
                description = "Settings for this principal's signed static Nix cache. Device keys authorize native Nix SSH reads or writes to this static cache; no daemon or build store is used.";
              };
              publicKeys = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Additional SSH public keys; combined with named device keys without revoking existing authorization.";
              };
              gcryptParticipants = mkOption {
                type = types.listOf fingerprint;
                default = [ ];
                description = "Additional public Git member fingerprints; combined with device keys and enabled recovery recipients for the effective participant policy.";
              };
              recovery = {
                enable = mkOption {
                  type = types.bool;
                  default = cfg.recovery.enable && config.backend != "nix-cache";
                  description = "Enable recovery for this encrypted principal; false opts out of the global policy. Static cache data has no decryption key.";
                };
                recipients = mkOption {
                  type = types.listOf fingerprint;
                  default = cfg.recovery.recipients;
                  description = "Override the global public recovery recipients for this principal; enabled recovery requires at least one recipient.";
                };
              };
              devices = mkOption {
                default = { };
                type = types.attrsOf (
                  types.submodule {
                    options = {
                      publicKey = mkOption {
                        type = types.str;
                        description = "This device public SSH key; its private key stays on the source machine.";
                      };
                      readOnly = mkOption {
                        type = types.bool;
                        default = false;
                        description = "Restrict this Git or Nix cache device to reads. Restic devices retain append-only access and cannot use this flag.";
                      };
                      gpgFingerprint = mkOption {
                        type = types.nullOr fingerprint;
                        default = null;
                        description = "Full public OpenPGP fingerprint for Git decryption membership, not a per-device write restriction.";
                      };
                    };
                  }
                );
                description = "Public device enrollment records retained in the Nix authority.";
              };
            };
          }
        )
      );
    };
    datasets = mkOption {
      default = { };
      type = types.attrsOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "Existing native ZFS dataset name under the declared pool.";
            };
            mountpoint = mkOption {
              type = types.str;
              description = "Expected mounted repository/cache path; bootstrap refuses missing or mismatched storage.";
            };
            principal = mkOption {
              type = types.str;
              description = "Declared account owning this dataset with its reserved numeric UID/GID.";
            };
            purpose = mkOption {
              type = types.enum [
                "user"
                "service"
                "git"
                "cache"
              ];
              description = "User data, service data, encrypted Git or static cache policy boundary.";
            };
            quotaBytes = mkOption {
              type = types.nullOr types.ints.positive;
              default = null;
              description = "Explicit snapshot-inclusive dataset quota in bytes; null blocks reconstruction.";
            };
            snapshots = mkOption {
              default = cfg.snapshotSchedules;
              type = snapshotSchedules;
              description = "Server-side ZFS snapshot schedules, inheriting the shared snapshotSchedules default for every backend. An explicit empty set disables scheduling without deleting existing snapshots. Applied separately through rsync-net snapshots configure.";
            };
          };
        }
      );
    };
    control = {
      dataset = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Explicit ZFS dataset name for reviewed storage init --control provisioning. Existing control storage may leave this unset.";
      };
      quotaBytes = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        description = "Snapshot-inclusive quota required when creating the control dataset through storage init.";
      };
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Keep an administrative catalog and encrypted recovery envelopes on preserved storage; publication requires separate reviewed control operations.";
      };
      path = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Approved existing root-owned 0700 directory on the verified ZFS pool, separate from every client repository; null blocks control publication.";
      };
    };
    manifest = mkOption {
      type = types.attrs;
      readOnly = true;
      description = "Non-secret desired state consumed by inspection, planning and reviewed bounded reconstruction.";
    };
  };
  config.rsyncNet.manifest =
    assert lib.assertMsg (lib.all (p: (p.backend == "nix-cache") == (p.cache != null)) (
      lib.attrValues cfg.principals
    )) "Only nix-cache principals have cache settings";
    assert lib.assertMsg (lib.all
      (
        principal:
        principal.backend != "restic"
        || lib.all (device: !device.readOnly) (lib.attrValues principal.devices)
      )
      (lib.attrValues cfg.principals)
    ) "Restic devices use append-only access; readOnly is only supported for Git and Nix caches";
    assert lib.assertMsg (
      !cfg.recovery.enable || cfg.recovery.recipients != [ ]
    ) "Enabled default recovery requires public recipients";
    assert lib.assertMsg (lib.all
      (
        principal:
        (!principal.recovery.enable || principal.recovery.recipients != [ ])
        && (principal.backend != "nix-cache" || !principal.recovery.enable)
      )
      (lib.attrValues cfg.principals)
    ) "Enabled principal recovery requires recipients and an encrypted backend";
    {
      schemaVersion = 1;
      inherit (cfg)
        mode
        connection
        setup
        pool
        control
        recovery
        ;
      principals = lib.mapAttrsToList (
        _: principal:
        (builtins.removeAttrs principal [ "devices" ])
        // {
          publicKeys = lib.sort builtins.lessThan (
            lib.unique (
              principal.publicKeys ++ map (device: device.publicKey) (lib.attrValues principal.devices)
            )
          );
          readOnlyKeys = lib.sort builtins.lessThan (
            lib.unique (
              map (device: device.publicKey) (
                builtins.filter (device: device.readOnly) (lib.attrValues principal.devices)
              )
            )
          );
          gcryptParticipants = lib.sort builtins.lessThan (
            lib.unique (
              principal.gcryptParticipants
              ++ builtins.filter (value: value != null) (
                map (device: device.gpgFingerprint) (lib.attrValues principal.devices)
              )
              ++ lib.optionals (
                principal.backend == "git" && principal.recovery.enable
              ) principal.recovery.recipients
            )
          );
        }
      ) cfg.principals;
      datasets = lib.attrValues cfg.datasets;
    };
}
