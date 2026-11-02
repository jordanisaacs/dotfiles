{ pkgs }:
let
  inherit (pkgs) lib;
  python = pkgs.python3.withPackages (packages: [ packages.secretstorage ]);
  password = "BootCacheFixture-9!";
  cloneRules = lib.mapAttrs (
    _: rule: {
      inherit (rule)
        enable
        order
        control
        modulePath
        args
        ;
    }
  );
in
pkgs.testers.runNixOSTest {
  name = "fingerprint-boot-keyring-unlock";
  nodes.machine =
    { config, ... }:
    {
      imports = [ ../modules/system/greetd/default.nix ];
      options.jd.graphical.enable = lib.mkEnableOption "graphical fixture";
      config = {
        virtualisation = {
          memorySize = 1536;
          cores = 2;
        };
        jd.greetd = {
          enable = true;
          bootKeyringUsers = [ "jd" ];
        };
        services = {
          greetd.settings.default_session.command = lib.mkForce "${python.interpreter} ${./greetd_greeter_fixture.py}";
          gnome.gnome-keyring.enable = true;
          fprintd.enable = true;
        };
        # Only biometric matching is a test double. All policy controls, Unix
        # password authentication, kernel key lookup and GNOME unlock are real.
        security.pam.services = {
          greetd.rules.auth.boot-keyring-load.settings.debug = true;
          greetd-fingerprint-probe = {
            useDefaultRules = false;
            rules = {
              account = cloneRules config.security.pam.services.greetd.rules.account;
              session = cloneRules config.security.pam.services.greetd.rules.session;
              auth = (cloneRules config.security.pam.services.greetd.rules.auth) // {
                fprintd = (cloneRules config.security.pam.services.greetd.rules.auth).fprintd // {
                  modulePath = "${pkgs.pam}/lib/security/pam_permit.so";
                };
              };
            };
          };
          greetd-password-probe = {
            useDefaultRules = false;
            rules = {
              account = cloneRules config.security.pam.services.greetd.rules.account;
              session = cloneRules config.security.pam.services.greetd.rules.session;
              auth = (cloneRules config.security.pam.services.greetd.rules.auth) // {
                fprintd = (cloneRules config.security.pam.services.greetd.rules.auth).fprintd // {
                  modulePath = "${pkgs.pam}/lib/security/pam_deny.so";
                };
              };
            };
          };
        };
        users.users = {
          jd = {
            isNormalUser = true;
            uid = 1000;
            initialPassword = password;
            linger = true;
          };
          bob = {
            isNormalUser = true;
            uid = 1001;
            initialPassword = "BobDifferentFixture";
            linger = true;
          };
        };
        environment.systemPackages = [
          pkgs.keyutils
          python
        ];
        environment.etc = {
          "keyring-pass-jd".text = password;
          # Deliberately match the disk fixture too: exclusion must prevent
          # release, rather than merely failing because Bob's secret differs.
          "keyring-pass-bob".text = password;
          "pam-keyring-probe.py".source = ./pam_keyring_probe.py;
          "keyring-fixture.py".source = ./keyring_fixture.py;
        };
        systemd.user.services.fixture-keyring = {
          wantedBy = [ "default.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --foreground --components=secrets --control-directory=%t/keyring --unlock";
            StandardInput = "file:/etc/keyring-pass-%u";
          };
        };
      };
    };

  testScript = ''
    import datetime
    import json
    import shlex

    def user(name, *arguments):
        uid = {"jd": 1000, "bob": 1001}[name]
        return shlex.join([
            "runuser", "-u", name, "--", "env",
            f"XDG_RUNTIME_DIR=/run/user/{uid}",
            f"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus",
            *arguments,
        ])

    def keyring(name, operation="status"):
        return json.loads(machine.succeed(user(name, "${python.interpreter}", "/etc/keyring-fixture.py", operation)))

    def lock(name="jd"):
        assert keyring(name, "lock")["locked"]

    def cache(value):
        # Public test-only credentials, confined to this disposable VM.
        program = "import subprocess; print(subprocess.run(['keyctl', 'padd', 'user', 'cryptsetup', '@u'], input=" + repr(value.encode()) + ", capture_output=True, check=True).stdout.decode().strip())"
        return machine.succeed(shlex.join(["${python.interpreter}", "-c", program])).strip()

    def authenticate(service="greetd-fingerprint-probe", name="jd", supplied="unused-fixture"):
        result = json.loads(machine.succeed(shlex.join([
            "systemd-run", "--quiet", "--wait", "--pipe", "--collect", "--property=KeyringMode=shared",
            "${python.interpreter}", "/etc/pam-keyring-probe.py", service, name, supplied,
            "--library", "${pkgs.pam}/lib/libpam.so.0",
        ])))
        if result["auth"] == 0:
            assert result.get("credentials") == 0, result
            assert result.get("delete_credentials") == 0, result
        return result

    start_all()
    machine.wait_for_unit("greetd.service")
    # Reaching Type=simple active is insufficient: greetd can fail moments later
    # during its unauthenticated greeter's PAM credential/session startup.
    machine.wait_for_file("/tmp/greetd-greeter-started", timeout=datetime.timedelta(seconds=20))
    for name in ("jd", "bob"):
        uid = {"jd": 1000, "bob": 1001}[name]
        machine.wait_for_unit(f"user@{uid}.service")
        machine.wait_until_succeeds(user(name, "${python.interpreter}", "/etc/keyring-fixture.py", "initialize"))
        assert keyring(name)["canary"]
        machine.succeed(shlex.join(["${python.interpreter}", "-c", "from pathlib import Path; assert b'KeyringFixtureCanary-2026' not in Path('/home/" + name + "/.local/share/keyrings/login.keyring').read_bytes()"]))
        lock(name)

    serial = cache("${password}")
    result = authenticate()
    assert result["auth"] == 0 and result["session"] == 0, result
    assert keyring("jd")["canary"], "A matched fingerprint plus boot cache did not unlock the encrypted keyring"
    lock()

    result = authenticate("greetd-password-probe", supplied="DefinitelyWrongFixture")
    assert result["auth"] != 0, result
    assert keyring("jd")["locked"], "Failed login unlocked secrets through the cached boot password"

    machine.succeed("keyctl unlink " + serial + " @u")
    serial = cache("IncorrectCachedFixture")
    result = authenticate("greetd-password-probe", supplied="${password}")
    assert result["auth"] == 0 and result["session"] == 0, result
    assert keyring("jd")["canary"], "A wrong cache clobbered an explicitly supplied correct login password"
    lock()

    machine.succeed("keyctl unlink " + serial + " @u")
    result = authenticate()
    assert result["auth"] == 0 and result["session"] == 0, result
    assert keyring("jd")["locked"], "Missing cache must leave the encrypted keyring locked"

    serial = cache("${password}")
    result = authenticate(name="bob")
    assert result["auth"] == 0 and result["session"] == 0, result
    assert keyring("bob")["locked"], "The boot password was released to an unlisted user"
    assert keyring("jd")["locked"]
    machine.succeed("systemd-run --quiet --wait --pipe --collect --property=KeyringMode=shared keyctl timeout " + serial + " 1")
    machine.sleep(2)
    result = authenticate()
    assert result["auth"] == 0 and result["session"] == 0, result
    assert keyring("jd")["locked"], "Expired cache must leave the encrypted keyring locked"
    print("Native PAM, encrypted GNOME keyring and cached/missing/wrong/expired credential checks passed")
  '';
}
