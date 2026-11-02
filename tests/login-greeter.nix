{
  pkgs,
  bootKeyring ? false,
}:
let
  terminalProbe = pkgs.writers.writePython3Bin "greeter-terminal-probe" { } ''
    import json
    import os
    from pathlib import Path
    import pwd

    account = pwd.getpwuid(os.getuid())
    result = {
        "uid": os.getuid(),
        "home": os.environ.get("HOME"),
        "session": os.environ.get("XDG_SESSION_ID"),
        "type": os.environ.get("XDG_SESSION_TYPE"),
        "shell": os.getppid(),
    }
    (Path(account.pw_dir) / "terminal-result.json").write_text(json.dumps(result))
  '';
  sessionFixture = pkgs.writers.writePython3Bin "greeter-session-fixture" { } ''
    import argparse
    import json
    import os
    from pathlib import Path
    import pwd
    import time

    parser = argparse.ArgumentParser()
    parser.add_argument("--window-manager", required=True)
    arguments = parser.parse_args()
    account = pwd.getpwuid(os.getuid())
    home = Path(account.pw_dir)
    (home / "login-result.json").write_text(json.dumps({
        "uid": os.getuid(),
        "user": account.pw_name,
        "home": os.environ["HOME"],
        "manager": arguments.window_manager,
        "session": os.environ["XDG_SESSION_ID"],
        "sessionType": os.environ.get("XDG_SESSION_TYPE"),
    }))
    print("Authenticated session is running", flush=True)
    request = home / "exit-session"
    while not request.exists():
        time.sleep(0.1)
    request.unlink()
  '';
in
pkgs.testers.runNixOSTest {
  name = "system-login-window-manager-selection";
  nodes.machine = { lib, ... }: {
    imports = [
      ../modules/system/greetd
      ({ lib, ... }: {
        options.jd.graphical = {
          enable = lib.mkEnableOption "graphical login fixture";
          wayland.enable = lib.mkEnableOption "Wayland login fixture";
        };
      })
    ];
    jd = {
      graphical = {
        enable = true;
        wayland.enable = true;
      };
      greetd = {
        enable = true;
        bootKeyringUsers = lib.optionals bootKeyring [ "alice" ];
        # Reka sorts after Oxbow: this proves the actual declared default.
        defaultWindowManager = "reka";
      };
    };
    virtualisation.memorySize = 768;
    services = lib.mkIf bootKeyring {
      fprintd.enable = true;
      gnome.gnome-keyring.enable = true;
    };
    environment.systemPackages = [ terminalProbe ];
    users.users = lib.genAttrs [ "alice" "bob" ] (name: {
      isNormalUser = true;
      uid = if name == "alice" then 1000 else 1001;
      password = "fixture-password";
      homeMode = "0700";
    });
    systemd.tmpfiles.rules =
      map (name: "L+ /home/${name}/.winitrc - - - - ${sessionFixture}/bin/greeter-session-fixture")
        [
          "alice"
          "bob"
        ];
  };
  testScript = ''
    import json

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("greetd.service")

    def authenticate(username):
        machine.wait_until_tty_matches("1", "Username:")
        # Remembering a username can reopen its password prompt. Reset the
        # authentication conversation before selecting another account.
        machine.send_key("esc")
        machine.wait_until_tty_matches("1", r"(?s)\A(?!.*Password:).*Username:")
        machine.send_chars(username + "\n")
        machine.wait_until_tty_matches("1", "Password:")
        machine.send_chars("fixture-password\n")

    def login(username, expected_manager, uid):
        authenticate(username)
        try:
            machine.wait_for_file("/home/" + username + "/login-result.json", timeout=30)
        except Exception:
            print(machine.succeed("journalctl -b -u greetd.service --no-pager"))
            print(machine.succeed("cat /dev/vcs1"))
            raise
        result = json.loads(machine.succeed(
            "cat /home/" + username + "/login-result.json"))
        session_id = result.pop("session")
        assert result == {
            "uid": uid, "user": username, "home": "/home/" + username,
            "manager": expected_manager, "sessionType": "wayland",
        }, result
        assert machine.succeed(
            "loginctl show-session " + session_id + " -p Type --value").strip() == "wayland"

    def logout(username):
        machine.succeed("rm /home/" + username + "/login-result.json")
        machine.succeed("touch /home/" + username + "/exit-session")
        machine.wait_until_fails("pgrep -u " + username + " -f greeter-session-fixture")
        machine.wait_until_tty_matches("1", "Username:")

    with subtest("Greeter cannot read private user configuration before login"):
        machine.fail("runuser -u greeter -- test -r /home/alice/.winitrc")
        machine.fail("runuser -u greeter -- test -r /home/bob/.winitrc")

    with subtest("Nix default selects Reka for the authenticated user"):
        login("alice", "reka", 1000)
        logout("alice")

    with subtest("Login menu selects Oxbow for a different user"):
        machine.send_key("f3")
        machine.wait_until_tty_matches("1", "River \\(Oxbow\\)")
        machine.wait_until_tty_matches("1", "River \\(Reka\\)")
        # Tuigreet sorts names. Oxbow is the first actual session entry.
        machine.send_key("ret")
        login("bob", "oxbow", 1001)
        logout("bob")

    with subtest("A prior manual choice does not replace the Nix default"):
        login("alice", "reka", 1000)
        logout("alice")

    with subtest("Native free command opens the authenticated user's TTY shell"):
        machine.send_key("f2")
        machine.wait_until_tty_matches("1", "New command:")
        machine.send_key("ctrl-u")
        machine.send_chars("desktop-login --terminal\n")
        authenticate("bob")
        machine.wait_until_tty_matches("1", "bob@machine")
        machine.send_chars("greeter-terminal-probe\n")
        try:
            machine.wait_for_file("/home/bob/terminal-result.json", timeout=20)
        except Exception:
            print(" ".join(machine.succeed("cat /dev/vcs1").split()))
            raise
        terminal = json.loads(machine.succeed("cat /home/bob/terminal-result.json"))
        assert terminal["uid"] == 1001 and terminal["home"] == "/home/bob", terminal
        assert terminal["type"] == "tty", terminal
        assert machine.succeed(
            "loginctl show-session " + terminal["session"] + " -p Type --value"
        ).strip() == "tty"
        assert machine.succeed(
            "cat /proc/" + str(terminal["shell"]) + "/comm"
        ).strip() == "bash"
        machine.send_chars("exit\n")
        machine.wait_until_tty_matches("1", "Username:")

    with subtest("The Nix default also survives a previous free command"):
        login("alice", "reka", 1000)
        logout("alice")
  '';
}
