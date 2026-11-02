{ pkgs }:
let
  inherit (pkgs) lib;
  policy = builtins.fromJSON (builtins.readFile ../src/rsync_net/data/private-sshd-policy.json);
  evaluate =
    module:
    (import ../network {
      inherit pkgs;
      modules = [
        ../module.nix
        {
          rsyncNet = {
            connection.host = "fixture.example";
            principals.backup = {
              uid = 2000;
              gid = 2000;
              backend = "restic";
              dataset = "data1/backups/framework";
            };
            datasets.framework = {
              name = "data1/backups/framework";
              mountpoint = "/mnt/data1/backups/framework";
              principal = "backup";
              purpose = "user";
              quotaBytes = 1048576;
            };
            network = {
              requested = true;
              nodeName = "provider";
              tailnetSuffix = "fixture.ts.net";
              stateDirectory = "/mnt/data1/control/tailscale";
              tags = [ "tag:storage" ];
            };
          };
        }
        module
      ];
    }).plan;
  good = evaluate { };
  cacheSettings = {
    rsyncNet.principals.build-cache = {
      backend = "nix-cache";
    };
  };
  cache = evaluate cacheSettings;
  invalid = module: !(builtins.tryEval (builtins.deepSeq (evaluate module) true)).success;
in
assert good.blockers != [ ];
assert good.desiredFiles == [ ];
assert good.serveCommands == [ ];
assert policy.listenAddress == "127.0.0.1";
assert policy.port == 2222;
assert policy.configPath == "/usr/local/etc/rsync-net/sshd-private.conf";
assert policy.authorizedKeysRoot == "/usr/local/etc/rsync-net/authorized_keys";
assert good.privateSshConfigPath == policy.configPath;
assert good.centralAuthorizedKeysDirectory == policy.authorizedKeysRoot;
assert !good.deploymentReady && !good.applySupported;
assert invalid { rsyncNet.network.managedUsers = lib.mkForce [ "root" ]; };
assert invalid { rsyncNet.network.stateDirectory = lib.mkForce "/mnt/data1/."; };
assert invalid { rsyncNet.network.stateDirectory = lib.mkForce "/mnt/data1"; };
assert invalid { rsyncNet.network.stateDirectory = lib.mkForce "/mnt/data1/control/../tailscale"; };
assert invalid {
  rsyncNet.network.stateDirectory = lib.mkForce "/mnt/data1/backups/framework/state";
};
assert invalid { rsyncNet.network.stateDirectory = lib.mkForce "/mnt/data1/backups"; };
assert invalid { rsyncNet.network.privateSshPort = 22; };
assert cache.cacheEndpoints.build-cache == null;
assert cache.desiredFiles == [ ];
assert cache.serveCommands == [ ];
assert (evaluate { rsyncNet.mode = "private"; }).desiredFiles == [ ];
assert good.cacheEndpoints == { };
assert invalid { rsyncNet.control.path = "/mnt/data1/control"; };
assert invalid { rsyncNet.control.path = "/mnt/data1/control/tailscale/child"; };
pkgs.runCommand "rsync-net-network-policy-evaluation" { } ''
  touch "$out"
''
