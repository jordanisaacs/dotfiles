{ pkgs, homeManager }:
let
  inherit (pkgs) lib;
  key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB";
  member = lib.concatStrings (lib.replicate 40 "A");
  recovery = lib.concatStrings (lib.replicate 40 "B");
  homePath = "/tmp/rsync client-home";
  policy = {
    rsyncNet = {
      connection.host = "public.example.invalid";
      connection.port = 22022;
      pool.guid = "12345";
      recovery = {
        enable = true;
        recipients = [ recovery ];
      };
      principals = {
        files = {
          uid = 62001;
          gid = 62001;
          backend = "restic";
          dataset = "data1/files";
          devices.laptop.publicKey = key;
        };
        personal = {
          uid = 62002;
          gid = 62002;
          backend = "git";
          dataset = "data1/git/personal";
          devices.laptop = {
            publicKey = key;
            gpgFingerprint = member;
          };
        };
      };
      datasets = {
        files = {
          name = "data1/files";
          mountpoint = "/mnt/data1/files";
          principal = "files";
          purpose = "user";
          quotaBytes = 1048576;
        };
        personal = {
          name = "data1/git/personal";
          mountpoint = "/mnt/data1/git/personal";
          principal = "personal";
          purpose = "git";
          quotaBytes = 1048576;
        };
      };
    };
  };
  base = {
    home = {
      username = "client";
      homeDirectory = homePath;
      stateVersion = "25.11";
    };
    xdg = {
      enable = true;
      userDirs = {
        enable = true;
        documents = "${homePath}/Documents two";
        pictures = "${homePath}/Pictures";
      };
    };
    jd.rsyncNetClient = {
      enable = true;
      policyModules = [ policy ];
      endpoint = {
        host = "custom.example.invalid";
        port = 2222;
        publicHostKey = key;
      };
      bindings = {
        files = {
          principal = "files";
          device = "laptop";
          identityFile = "${homePath}/.local/state/rsync-net/keys/files";
        };
        personal = {
          principal = "personal";
          device = "laptop";
          identityFile = "${homePath}/.local/state/rsync-net/keys/personal";
        };
      };
      backups.documents = {
        enable = true;
        binding = "files";
        passwordFile = "${homePath}/secrets/restic-password";
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "30m";
        };
      };

    };
  };
  make =
    extra:
    (homeManager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        ../home-manager.nix
        base
        extra
      ];
    }).config;
  good = make { };
  machineIdentity = make {
    jd.rsyncNetClient.gitIdentity = {
      enable = true;
      device = "laptop";
      lookupCommand = [
        "/private/keyring"
        "lookup"
      ];
      storeCommand = [
        "/private/keyring"
        "store"
      ];
    };
  };
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
  runtimeTrust = make {
    jd.rsyncNetClient.endpoint = {
      publicHostKey = lib.mkForce null;
      knownHostsFile = "${homePath}/trust/known hosts";
    };
  };
  projected =
    cfg:
    assert lib.assertMsg (lib.all (a: a.assertion) cfg.assertions) "invalid client assertions";
    {
      ssh = toString cfg.home.file.".ssh/config".source;
      git = toString cfg.xdg.configFile."git/config".source;
      public = cfg.jd.rsyncNetClient.publicKeyFiles;
      restic = {
        inherit (cfg.services.restic.backups.rsync-net-documents)
          paths
          extraOptions
          initialize
          pruneOpts
          passwordFile
          ;
      };
    };
  invalid = extra: !(builtins.tryEval (builtins.deepSeq (projected (make extra)) true)).success;
  disabled = make { jd.rsyncNetClient.enable = lib.mkForce false; };
  evaluated = projected good;
  controller = import ../../default.nix {
    inherit pkgs;
    modules = [ ../../tests/framework-policy.nix ];
  };
  fixtureManifest =
    (import ../../default.nix {
      inherit pkgs;
      modules = [ policy ];
    }).manifest;
  publicFile = pkgs.writeText "rsync-client-public.pub" key;
in
assert !disabled.programs.ssh.enable && !disabled.services.restic.enable;
assert disabled.jd.rsyncNetClient.publicKeyFiles == { };
assert lib.elem pkgs.git-remote-gcrypt good.home.packages;
assert lib.elem pkgs.rsync good.home.packages;
assert builtins.hasAttr "rsync-net/git-identity.json" machineIdentity.xdg.configFile;
assert (builtins.elemAt machineIdentity.programs.git.includes 0).contents.gpg.format == "openpgp";
assert (builtins.elemAt machineIdentity.programs.git.includes 0).contents.user.signingKey == member;
assert invalid { jd.rsyncNetClient.endpoint.publicHostKey = lib.mkForce null; };
assert invalid privatePolicy;
assert !privateDisabled.programs.ssh.enable && !privateDisabled.services.restic.enable;
assert privateDisabled.jd.rsyncNetClient.publicKeyFiles == { };
assert invalid {
  jd.rsyncNetClient.bindings.files.identityFile = lib.mkForce "/nix/store/private-key";
};
assert invalid { jd.rsyncNetClient.bindings.files.device = lib.mkForce "missing"; };
assert invalid { jd.rsyncNetClient.backups.documents.passwordFile = lib.mkForce null; };
assert invalid { jd.rsyncNetClient.backups.documents.xdgDirectories = lib.mkForce [ ]; };

pkgs.runCommand "rsync-net-home-manager-client"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.openssh
      pkgs.git
      pkgs.restic
      controller.cli
    ];
    CLIENT_CONFIG = pkgs.writeText "rsync-client-config.json" (
      builtins.toJSON (
        evaluated
        // {
          inherit homePath member recovery;
          publicDefault = projected publicDefault;
          runtimeTrustSsh = toString runtimeTrust.home.file.".ssh/config".source;
          service = good.systemd.user.services.restic-backups-rsync-net-documents;
          timer = good.systemd.user.timers.restic-backups-rsync-net-documents;
          publicSource = toString good.xdg.configFile."rsync-net/public-keys/files.pub".source;
          backupDescriptor = toString good.xdg.configFile."rsync-net/backups/documents.json".source;
        }
      )
    );
  }
  ''
    python ${./home-manager.py}
    rsync-net --manifest ${fixtureManifest} enroll --principal files --device declarative --public-key ${publicFile} --output "$TMPDIR/enrollment" > "$TMPDIR/enrolled.json"
    test ! -e "$TMPDIR/enrollment/device-key"
    touch "$out"
  ''
