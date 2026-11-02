{ pkgs }:
let
  inherit (pkgs) lib;
  key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB";
  signingKey = "fixture:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  policy = {
    rsyncNet = {
      connection.host = "public.example.invalid";
      connection.port = 22022;
      pool.guid = "12345";
      principals = {
        database = {
          uid = 62001;
          gid = 62001;
          backend = "restic";
          dataset = "data1/service/database";
          devices.server.publicKey = key;
        };
        cache = {
          uid = 62002;
          gid = 62002;
          backend = "nix-cache";
          dataset = "data1/cache";
          cache.signingPublicKeys = [ signingKey ];
          devices.daemon = {
            publicKey = key;
            readOnly = true;
          };
        };
      };
      datasets = {
        database = {
          name = "data1/service/database";
          mountpoint = "/mnt/data1/service/database";
          principal = "database";
          purpose = "service";
          quotaBytes = 1048576;
        };
        cache = {
          name = "data1/cache";
          mountpoint = "/mnt/data1/cache";
          principal = "cache";
          purpose = "cache";
          quotaBytes = 1048576;
        };
      };
    };
  };
  base = {
    boot.isContainer = true;
    system.stateVersion = "25.11";
    # OpenSSH checks owners of included files; sandbox builds run as nixbld,
    # while the installed systemd include belongs to a different store owner.
    # The local/VM proxy is unrelated to these remote client aliases.
    programs.ssh.systemd-ssh-proxy.enable = false;
    jd.rsyncNetClient = {
      enable = true;
      policyModules = [ policy ];
      endpoint = {
        host = "custom.example.invalid";
        port = 2222;
        publicHostKey = key;
      };
      bindings = {
        database = {
          principal = "database";
          device = "server";
          identityFile = "/run/service secrets/ssh-key";
        };
        cache = {
          principal = "cache";
          device = "daemon";
          identityFile = "/run/cache secrets/root-ssh-key";
        };
      };
      serviceBackups.database = {
        enable = true;
        binding = "database";
        paths = [ "/var/lib/database/export" ];
        passwordFile = "/run/service secrets/restic-password";
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };
      daemonCaches.private = {
        enable = true;
        binding = "cache";
      };
    };
  };
  make =
    extra:
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        ../nixos.nix
        base
        extra
      ];
    }).config;
  good = make { };
  publicDefault = make {
    jd.rsyncNetClient.endpoint = {
      host = lib.mkForce null;
      port = lib.mkForce null;
    };
  };
  privatePolicy = {
    jd.rsyncNetClient.policyModules = [ { rsyncNet.mode = "private"; } ];
  };
  privateDisabled = make (
    lib.recursiveUpdate privatePolicy {
      jd.rsyncNetClient.enable = lib.mkForce false;
    }
  );
  projected =
    cfg:
    assert lib.assertMsg (lib.all (a: a.assertion) cfg.assertions) "invalid system client assertions";
    {
      ssh = cfg.environment.etc."ssh/ssh_config".text;
      urls = cfg.jd.rsyncNetClient.cacheStoreUrls;
      keys = cfg.nix.settings.trusted-public-keys;
      substituters = cfg.nix.settings.substituters;
      requireSigs = cfg.nix.settings.require-sigs or true;
      service = cfg.systemd.services.restic-backups-rsync-net-database.serviceConfig;
      environment = cfg.systemd.services.restic-backups-rsync-net-database.environment;
      timer = cfg.systemd.timers.restic-backups-rsync-net-database.timerConfig;
    };
  invalid = extra: !(builtins.tryEval (builtins.deepSeq (projected (make extra)) true)).success;
  disabled = make { jd.rsyncNetClient.enable = lib.mkForce false; };
in
assert disabled.jd.rsyncNetClient.cacheStoreUrls == { };
assert !(disabled.services.restic.backups ? rsync-net-database);
assert invalid { jd.rsyncNetClient.serviceBackups.database.passwordFile = lib.mkForce null; };
assert invalid { jd.rsyncNetClient.serviceBackups.database.paths = lib.mkForce [ ]; };
assert invalid { nix.settings.require-sigs = false; };
assert invalid privatePolicy;
assert privateDisabled.jd.rsyncNetClient.cacheStoreUrls == { };
assert !(privateDisabled.services.restic.backups ? rsync-net-database);
assert !(lib.hasInfix "rsync-net-" privateDisabled.environment.etc."ssh/ssh_config".text);
assert invalid {
  jd.rsyncNetClient.policyModules = [
    {
      rsyncNet.principals.cache.devices.daemon.readOnly = lib.mkForce false;
    }
  ];
};
assert invalid {
  jd.rsyncNetClient.policyModules = [
    {
      rsyncNet.principals.cache.cache.signingPublicKeys = lib.mkForce [ ];
    }
  ];
};
pkgs.runCommand "rsync-net-nixos-client"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.openssh
      pkgs.restic
    ];
    CLIENT_CONFIG = pkgs.writeText "rsync-system-client.json" (
      builtins.toJSON (
        projected good
        // {
          inherit signingKey;
          publicDefault = projected publicDefault;
        }
      )
    );
  }
  ''
    python ${./nixos.py}
    touch "$out"
  ''
