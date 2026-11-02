{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.rsyncNet.network;
  principals = config.rsyncNet.principals or { };
  account = types.strMatching "[a-z][a-z0-9_-]{0,30}";
  label = types.strMatching "[a-z0-9]([a-z0-9-]*[a-z0-9])?";
  statePath = types.strMatching "/mnt/[A-Za-z0-9_./-]+";
  privatePolicy = builtins.fromJSON (
    builtins.readFile ../src/rsync_net/data/private-sshd-policy.json
  );
  users = lib.sort builtins.lessThan (lib.unique cfg.managedUsers);
  stateParts = if cfg.stateDirectory == null then [ ] else lib.splitString "/" cfg.stateDirectory;
  repositoryPaths = map (dataset: dataset.mountpoint) (
    lib.attrValues (config.rsyncNet.datasets or { })
  );
  containsPath = parent: child: parent == child || lib.hasPrefix "${parent}/" child;
  enabled = false; # Private transport remains an inactive prototype.
  blockers = lib.optionals cfg.requested (
    [ "Private transport mode is incomplete; activation is disabled" ]
    ++ lib.optional (cfg.nodeName == null) "Tailscale node name is not selected"
    ++ lib.optional (cfg.tailnetSuffix == null) "tailnet DNS suffix is not selected"
    ++ lib.optional (
      cfg.stateDirectory == null
    ) "durable root-only Tailscale state location is not selected"
    ++ lib.optional (cfg.tags == [ ]) "least-privilege server tag/grants are not selected"
    ++ lib.optional (users == [ ]) "no routine SSH accounts are declared"
    ++
      lib.optional (cfg.privateSshPort != privatePolicy.port)
        "selected private port differs from the account bootstrap's port; controller integration is required"
  );
  # This renderer is a transport fixture/candidate. Production activation must
  # consume account-bootstrap authorization, not replace it with a second database.
  privateConfig =
    lib.replaceStrings
      [
        "@listen_address@"
        "@port@"
        "@pid_file@"
        "@host_key@"
        "@authorized_keys_root@"
        "@managed_users@"
      ]
      [
        privatePolicy.listenAddress
        (toString cfg.privateSshPort)
        privatePolicy.pidFile
        privatePolicy.hostKey
        privatePolicy.authorizedKeysRoot
        (if users == [ ] then "!root" else lib.concatStringsSep " " users)
      ]
      (builtins.readFile ../src/rsync_net/data/private-sshd.conf.in);
  dnsName =
    if cfg.nodeName == null || cfg.tailnetSuffix == null then
      null
    else
      "${cfg.nodeName}.${cfg.tailnetSuffix}";
in
{
  options.rsyncNet.network = {
    requested = mkOption {
      type = types.bool;
      default = false;
      description = "Prepare a tailnet-only service transport candidate; does not enroll or install.";
    };
    nodeName = mkOption {
      type = types.nullOr label;
      default = null;
      description = "Stable Tailscale node label; null blocks an activation candidate.";
    };
    tailnetSuffix = mkOption {
      type = types.nullOr (types.strMatching "[a-z0-9.-]+\\.ts\\.net");
      default = null;
      description = "Tailnet DNS suffix used to derive private SSH service endpoints.";
    };
    stateDirectory = mkOption {
      type = types.nullOr statePath;
      default = null;
      description = "Approved dedicated root-owned 0700 state directory on durable storage; never a backup repository.";
    };
    tags = mkOption {
      type = types.listOf (types.strMatching "tag:[a-z][a-z0-9-]*");
      default = [ ];
      description = "Least-privilege server tags requiring corresponding Tailnet grants; no tag or ACL is created here.";
    };
    managedUsers = mkOption {
      type = types.listOf account;
      default = map (p: p.name) (lib.attrValues (config.rsyncNet.principals or { }));
      description = "Routine private SSH accounts, derived from declared principals by default; root is forbidden.";
    };
    privateSshPort = mkOption {
      type = types.port;
      default = privatePolicy.port;
      description = "Loopback OpenSSH backend port; must match the shared account bootstrap policy and differ from public SSH.";
    };
    plan = mkOption {
      type = types.attrs;
      readOnly = true;
      description = "Read-only transport activation candidate and blockers; account reconstruction does not apply it.";
    };
  };

  config.rsyncNet.network.plan =
    assert lib.assertMsg (!lib.elem "root" users) "Root cannot be a routine service account";
    assert lib.assertMsg (
      cfg.privateSshPort != 22
    ) "Private SSH backend must not reuse public administrative port 22";
    assert lib.assertMsg (
      cfg.stateDirectory == null
      || (
        builtins.length stateParts >= 4
        && !lib.elem "." stateParts
        && !lib.elem ".." stateParts
        && !lib.elem "" (lib.drop 1 stateParts)
      )
    ) "State path must be canonical";
    assert lib.assertMsg (
      cfg.stateDirectory == null
      || !lib.any (
        path: containsPath path cfg.stateDirectory || containsPath cfg.stateDirectory path
      ) repositoryPaths
    ) "Tailscale secret state must be separate from every declared repository/cache path";
    assert lib.assertMsg (
      cfg.stateDirectory == null
      || (config.rsyncNet.control.path or null) == null
      || !(
        containsPath config.rsyncNet.control.path cfg.stateDirectory
        || containsPath cfg.stateDirectory config.rsyncNet.control.path
      )
    ) "Tailscale identity state must be separate from administrative control storage";
    {
      schemaVersion = 1;
      inherit (cfg) requested;
      deploymentReady = false;
      applySupported = false;
      inherit blockers dnsName;
      mode = "userspace-networking";
      administrativeEndpoint = "existing public ordinary SSH, unchanged";
      accountIntegration = {
        status = "separate transport prototype; not consumed by the account bootstrap";
        productionSshConfigAuthority = "account bootstrap staged private sshd configuration";
        fixtureSshConfigOnly = true;
        controllerPrivateSshPort = privatePolicy.port;
        cacheReaderTransport = "tailnet-ssh; root-controlled per-key forced commands";
      };
      centralAuthorizedKeysDirectory = privatePolicy.authorizedKeysRoot;
      privateSshConfigPath = privatePolicy.configPath;
      secretState = {
        path = cfg.stateDirectory;
        owner = "root";
        mode = "0700";
        preserveIdentity = true;
      };
      desiredFiles =
        lib.optional (enabled && users != [ ]) {
          path = privatePolicy.configPath;
          owner = "root";
          mode = "0600";
          contents = privateConfig;
        }
        ++ lib.optional (enabled && cfg.stateDirectory != null) {
          path = "/etc/rc.conf.d/tailscaled";
          owner = "root";
          mode = "0600";
          contents = ''
            tailscaled_enable="YES"
            tailscaled_state_dir="${cfg.stateDirectory}"
            tailscaled_tun_dev="userspace-networking"
            tailscaled_exitnode_enable="NO"
          '';
        };
      enrollmentArguments = [
        "--accept-dns=false"
        "--accept-routes=false"
        "--ssh=false"
        "--advertise-exit-node=false"
      ]
      ++ lib.optional (cfg.nodeName != null) "--hostname=${cfg.nodeName}"
      ++ lib.optional (cfg.tags != [ ]) "--advertise-tags=${lib.concatStringsSep "," cfg.tags}";
      serveCommands = lib.optionals enabled [
        [
          "/usr/local/bin/tailscale"
          "serve"
          "--bg"
          "--tcp=22"
          "tcp://${privatePolicy.listenAddress}:${toString cfg.privateSshPort}"
        ]
      ];
      cacheEndpoints = lib.mapAttrs (
        name: _: if enabled && dnsName != null then "ssh://${name}@${dnsName}" else null
      ) (lib.filterAttrs (_: principal: principal.backend == "nix-cache") principals);
      requiredVerification = [
        "wire the account manifest into this transport plan; use the account bootstrap's staged private sshd config as the single production authority"
        "provider-approved OS/package refresh and FreeBSD Tailscale Serve/Tailnet Lock execution"
        "existing public administrative SSH access remains usable"
        "all public sshd authorization paths/commands/CAs and password authentication reject every routine identity"
        "managed public-default authorized key files are absent and all central enforcement paths root-owned/client-unwritable"
        "private sshd native configuration, forced command scope, user switching and negative public login tests"
        "durable secret state path and ancestors cannot be accessed by any uploader; missing/unmounted backend aborts startup"
        "node has a valid Tailnet Lock signature and is not made a signing authority"
        "complete tailnet policy grants intended clients service ports and prevents storage-node lateral connections"
        "Serve backend listeners are loopback-only; userspace mode creates no public/ordinary tail-IP service listener"
        "Funnel is disabled and no TS_SERVE_ALLOW_ALL_INTERFACES override is set"
        "Nix cache serving uses an approved provider-native Nix executable under each principal UID; no daemon/local build store or remote builders"
        "cache clients verify enrolled SSH host keys and configured Nix signing keys; no trusted=true signature bypass"
        "restore ordinary service startup after update without resetting or copying the node identity to another machine"
      ];
    };
}
