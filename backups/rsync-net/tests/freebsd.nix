{ pkgs }:
let
  inherit (pkgs) lib;
  image = import ./freebsd-image.nix { inherit pkgs; };
  packages = import ./freebsd-packages.nix { inherit pkgs; };
  fixture.rsyncNet = {
    mode = "public";
    connection.host = "192.168.10.1";
    setup = {
      enable = true;
      backends = [
        "restic"
        "git"
      ];
      expectedRelease = "14.4-RELEASE";
    };
    control = {
      enable = true;
      path = "/mnt/data1/control";
    };
    principals = lib.genAttrs [ "backup-a" "backup-b" "git-host" ] (name: {
      uid =
        if name == "backup-a" then
          62001
        else if name == "backup-b" then
          62002
        else
          61003;
      gid =
        if name == "backup-a" then
          62001
        else if name == "backup-b" then
          62002
        else
          61003;
      backend = if name == "git-host" then "git" else "restic";
      dataset = "data1/${name}";
    });
    datasets = lib.genAttrs [ "backup-a" "backup-b" "git-host" ] (name: {
      name = "data1/${name}";
      mountpoint = "/mnt/data1/${name}";
      principal = name;
      purpose = if name == "git-host" then "git" else "user";
      quotaBytes = 268435456;
    });
  };
  controller = import ../default.nix {
    inherit pkgs;
    modules = [ ./framework-policy.nix ];
  };
  fixtureManifest =
    (import ../default.nix {
      inherit pkgs;
      modules = [ fixture ];
    }).manifest;
  # These keys authenticate only disposable, isolated regression machines.
  keys = pkgs.runCommand "freebsd-regression-keys" { nativeBuildInputs = [ pkgs.openssh ]; } ''
    mkdir "$out"
    ssh-keygen -q -t ed25519 -N "" -C disposable-admin -f "$out/admin"
    ssh-keygen -q -t ed25519 -N "" -C disposable-controller -f "$out/controller"
    ssh-keygen -q -t ed25519 -N "" -C disposable-provider -f "$out/host"
  '';
  seed =
    pkgs.runCommand "freebsd-regression-seed.iso"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.xorriso
        ];
      }
      ''
        python3 - ${keys} <<'PY'
        import json
        import pathlib
        import sys
        keys = pathlib.Path(sys.argv[1])
        config = {
            "users": [{"name": "root", "ssh_authorized_keys": [(keys / name).read_text().strip() for name in ("admin.pub", "controller.pub")]}],
            "ssh_pwauth": False,
            "ssh_keys": {
                "ed25519_private": (keys / "host").read_text(),
                "ed25519_public": (keys / "host.pub").read_text(),
            },
            "write_files": [
            # The pinned regression image must not run live OS updates at first boot.
            {"path": "/etc/rc.conf.d/firstboot_freebsd_update", "content": "firstboot_freebsd_update_enable=\"NO\"\n"},
            # Redirect the ordinary provider package source to a read-only,
            # signed fixture mirror; no packages are installed by nuageinit.
            {"path": "/etc/pkg/FreeBSD.conf", "content": "FreeBSD: { url: \"file:///packages\", mirror_type: \"none\", signature_type: \"fingerprints\", fingerprints: \"/usr/share/keys/pkg\", enabled: yes }\n"},
                {"path": "/etc/rc.conf.d/sshd", "content": "sshd_enable=\"YES\"\n"},
                {"path": "/etc/syslog.d/rsync-test.conf", "content": "auth.info;authpriv.info\t/var/log/rsync-test-auth.log\n"},
                {"path": "/var/log/rsync-test-auth.log", "content": "", "permissions": "0600"},
                {"path": "/etc/ssh/sshd_config", "content": "PermitRootLogin prohibit-password\nPasswordAuthentication no\nKbdInteractiveAuthentication yes\nListenAddress 192.168.10.1\nHostKey /etc/ssh/ssh_host_ed25519_key\nUsePAM yes\n"},
            ],
        }
        pathlib.Path("user-data").write_text("#cloud-config\n" + json.dumps(config))
        pathlib.Path("meta-data").write_text(json.dumps({"instance-id": "rsync-net-freebsd-regression", "local-hostname": "provider"}))
        pathlib.Path("network-config").write_text(json.dumps({"version": 2, "ethernets": {"vtnet0": {"dhcp4": False, "addresses": ["192.168.10.1/24"]}}}))
        PY
        xorriso -as mkisofs -quiet -volid cidata -joliet -rock -output "$out" user-data meta-data network-config
      '';
  settings = pkgs.writeText "freebsd-qemu.json" (
    builtins.toJSON {
      inherit image seed packages;
      qemu = "${pkgs.qemu_test}/bin/qemu-system-x86_64";
      qemuImg = "${pkgs.qemu_test}/bin/qemu-img";
    }
  );
  launcher = pkgs.writeText "freebsd-qemu.py" (builtins.readFile ./freebsd-qemu.py);
  runner = pkgs.writeScript "run-provider-vm" ''
    #!${pkgs.python3}/bin/python3
    import runpy
    import sys
    sys.argv.insert(1, ${builtins.toJSON (toString settings)})
    runpy.run_path(${builtins.toJSON (toString launcher)}, run_name="__main__")
  '';
in
pkgs.testers.runNixOSTest (
  { config, ... }:
  {
    name = "rsync-net-native-freebsd";
    globalTimeout = 600;
    nodes.admin = {
      virtualisation.vlans = [ 1 ];
      networking.useDHCP = false;
      networking.interfaces.eth1.ipv4.addresses = [
        {
          address = "192.168.10.2";
          prefixLength = 24;
        }
        {
          # Routine jobs and administrative access have separate sources in
          # native OpenSSH's per-source penalty accounting.
          address = "192.168.10.3";
          prefixLength = 24;
        }
        {
          address = "192.168.10.4";
          prefixLength = 24;
        }
      ];
      environment = {
        systemPackages = [
          controller.cli
          pkgs.openssh
          pkgs.python3
          pkgs.restic
          pkgs.rsync
          pkgs.git
          pkgs.git-remote-gcrypt
          pkgs.gnupg
        ];
        etc = {
          "rsync-base.json".source = fixtureManifest;
          "rsync-test-module-path".text = "${controller.cli}/${pkgs.python3.sitePackages}";
          "freebsd-test-admin-key".source = "${keys}/admin";
          "freebsd-test-controller-key".source = "${keys}/controller";
          "freebsd-test-host-key".source = "${keys}/host.pub";
        };
      };
    };
    driverConfiguration.vms = lib.mkForce {
      admin = {
        name = "admin";
        start_script = lib.getExe config.nodes.admin.system.build.vm;
      };
      provider = {
        name = "provider";
        start_script = runner;
      };
    };
    testScript = builtins.readFile ./freebsd.py;
  }
)
