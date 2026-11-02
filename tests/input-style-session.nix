{ pkgs, homeConfiguration }:
let
  macHome = homeConfiguration.extendModules {
    modules = [
      ({ lib, ... }: {
        jd.inputStyle = lib.mkForce "mac";
        machineData = lib.mkForce (
          homeConfiguration.config.machineData
          // {
            inputRemapping = {
              enable = true;
              users = [ homeConfiguration.config.home.username ];
            };
          }
        );
      })
    ];
  };
  home = macHome.config;
  username = home.home.username;
  directory = home.home.homeDirectory;
  bridge = home.home.file."${directory}/.config/systemd/user/desktop-input-bridge.service".source;
  python = pkgs.python3.withPackages (p: [ p.evdev ]);
in
import ./desktop-session.nix {
  inherit pkgs;
  homeConfiguration = macHome;
  nativeInput = true;
  extraModules = [
    ../modules/system/graphical/input-style.nix
    ({ config, ... }: {
      jd.graphical.inputRemapping = {
        enable = true;
        users = [ username ];
        # This native event viewer is the synthetic GUI application under test.
        applications = (import ../lib/mac-shortcuts.nix).applications ++ [ "wev" ];
      };
      boot.kernelModules = [ "uinput" ];
      environment.etc = {
        "mac-input-vm".text = "isolated regression VM";
        "mac-input-events.py".source = ./mac_input_events.py;
        "firefox-input-probe.py".source = ./firefox_input_probe.py;
        "firefox-input-preferences.json".text =
          builtins.toJSON home.programs.firefox.profiles.personal.settings;
      };
      environment.systemPackages = [
        pkgs.wev
        pkgs.kbd
        pkgs.waylock
        pkgs.geckodriver
        pkgs.firefox
        pkgs.wl-clipboard
        pkgs.kdePackages.dolphin
        pkgs.ghostty
        python
      ];
      virtualisation.memorySize = pkgs.lib.mkForce 3072;
      programs.dconf.enable = true;
      services.getty.autologinUser = username;
      # The production Tuigreet supplies this PAM metadata before session open.
      # This fixture auto-login has no Tuigreet authentication exchange.
      security.pam.services.greetd.rules.session.input-test-environment = {
        order = config.security.pam.services.greetd.rules.session.login.order - 10;
        control = "required";
        modulePath = "${pkgs.pam}/lib/security/pam_env.so";
        args = [
          "conffile=${pkgs.writeText "mac-input-pam-env" "XDG_SESSION_TYPE DEFAULT=wayland OVERRIDE=wayland\n"}"
        ];
      };
      security.pam.services.waylock = { };
      systemd.tmpfiles.rules = [
        "d ${directory}/.config/gtk-3.0 0755 ${username} users -"
        "L+ ${directory}/.config/gtk-3.0/settings.ini - - - - ${
          home.xdg.configFile."gtk-3.0/settings.ini".source
        }"
        "L+ ${directory}/.config/systemd/user/desktop-input-bridge.service - - - - ${bridge}"
        "L+ ${directory}/.config/systemd/user/graphical-session.target.wants/desktop-input-bridge.service - - - - ${bridge}"
      ];
      systemd.services.mac-input-source = {
        serviceConfig = {
          ExecStart = "${python}/bin/python /etc/mac-input-events.py source";
          Type = "simple";
        };
      };
    })
  ];
  testScriptOverride = ''
    import json
    import shlex
    import time
    from datetime import timedelta

    start_all()
    runtime = "/run/user/1000"
    def user(*arguments):
        return shlex.join(["runuser", "-u", "${username}", "--", "env",
                           "XDG_RUNTIME_DIR=" + runtime,
                           "DBUS_SESSION_BUS_ADDRESS=unix:path=" + runtime + "/bus", *arguments])
    def state():
        return json.loads(machine.succeed("${python}/bin/python /etc/mac-input-events.py sessions"))
    def wait_session(kind):
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            active = state()
            if len(active) == 1 and active[0]["Type"] == kind:
                return active[0]
            time.sleep(0.1)
        raise AssertionError("No active " + kind + " session: " + repr(state()))
    def chord(remapped, caps=False):
        keys = " LEFTMETA CAPSLOCK C" if caps else ""
        observed = json.loads(machine.succeed("${python}/bin/python /etc/mac-input-events.py chord" + keys))
        assert observed, "Synthetic chord produced no output"
        for modifiers in observed:
            assert modifiers["control"] == remapped, observed
            assert modifiers["command"] != remapped, observed
            assert modifiers["option"] == caps, observed
    def native_key(*keys):
        machine.succeed("${python}/bin/python /etc/mac-input-events.py chord " + " ".join(keys))

    machine.wait_for_unit("greetd.service")
    machine.wait_for_unit("user@1000.service")
    try:
        machine.wait_until_succeeds(user("systemctl", "--user", "is-active", "river-wm-oxbow.service"), timeout=timedelta(seconds=45))
        machine.wait_until_succeeds(user("systemctl", "--user", "is-active", "desktop-input-bridge.service"), timeout=timedelta(seconds=45))
    except Exception:
        print(machine.succeed("journalctl -b -u greetd -u desktop-input --no-pager"))
        print(machine.succeed("journalctl -b _UID=1000 --no-pager -n 160"))
        raise
    machine.wait_for_unit("desktop-input.service")
    assert not {"input", "uinput"}.intersection(machine.succeed("id -nG ${username}").split())
    assert machine.succeed("systemctl show desktop-input -p User --value").strip() == "xremap"
    wait_session("wayland")
    environment = json.loads(machine.succeed(user("systemctl", "--user", "show-environment", "--output=json")))
    oxenv = "OXBOW_SOCKET=" + environment["OXBOW_SOCKET"]
    wayland = "WAYLAND_DISPLAY=" + environment["WAYLAND_DISPLAY"]
    def ox(*arguments):
        return user("env", oxenv, "${pkgs.oxbow}/bin/oxctl", *arguments)
    bindings = json.loads(machine.succeed(ox("keymap", "list", "--json")))
    assert bindings["mode"] == "mac", bindings
    active_keys = {binding["keybind"] for binding in bindings["bindings"] if binding["mode"] == "mac"}
    assert "Super+Alt+space" in active_keys, active_keys
    assert "Super+space" in active_keys and "Super+Tab" in active_keys, active_keys
    assert not active_keys.intersection({"Super+c", "Super+v", "Super+x", "Super+a", "Super+w", "Super+q"}), active_keys
    machine.succeed(user("env", wayland, "${pkgs.uwsm}/bin/uwsm", "app", "-t", "service", "--", "${pkgs.wev}/bin/wev"))
    machine.wait_until_succeeds(ox("window", "focus", "match", "--app-id", "^wev$"))
    machine.succeed("systemctl start mac-input-source")
    machine.wait_for_file("/run/mac-input/ready")
    machine.succeed("udevadm settle")
    time.sleep(1)
    chord(True)

    native_key("LEFTMETA", "SPACE")
    machine.wait_until_succeeds(user("pgrep", "--exact", "fuzzel"), timeout=timedelta(seconds=10))
    native_key("ESC")
    machine.wait_until_fails(user("pgrep", "--exact", "fuzzel"), timeout=timedelta(seconds=10))
    machine.succeed(ox("window", "focus", "match", "--app-id", "^wev$"))
    def presentation():
        windows = json.loads(machine.succeed(ox("window", "list", "--json")))
        return next(window["presentation"] for window in windows if window["app_id"] == "wev")
    original_presentation = presentation()
    native_key("LEFTMETA", "LEFTALT", "SPACE")
    assert presentation() == "floating", presentation()
    native_key("LEFTMETA", "LEFTALT", "SPACE")
    assert presentation() == original_presentation, presentation()
    native_key("LEFTMETA", "LEFTCTRL", "F")
    assert presentation() == "fullscreen", presentation()
    native_key("LEFTMETA", "LEFTCTRL", "F")
    assert presentation() == original_presentation, presentation()

    # Firefox uses native Command accelerators rather than a Control swap.
    # Inspect actual chrome widgets through WebDriver, and inject physical
    # events only through the VM's root-owned synthetic keyboard.
    machine.succeed(user("${pkgs.dconf}/bin/dconf", "write", "/org/gnome/desktop/interface/gtk-key-theme",
                         ${
                           builtins.toJSON ("'" + home.dconf.settings."org/gnome/desktop/interface".gtk-key-theme + "'")
                         }))
    machine.succeed(user("systemd-run", "--user", "--unit=mac-firefox-driver", "--collect", "--",
                         "${pkgs.geckodriver}/bin/geckodriver", "--allow-system-access", "--port", "4444"))
    browser = "${python}/bin/python /etc/firefox-input-probe.py "
    machine.succeed(browser + "start ${pkgs.firefox}/bin/firefox /etc/firefox-input-preferences.json")
    machine.wait_until_succeeds(ox("window", "focus", "match", "--app-id", "firefox"))
    def browser_state():
        return json.loads(machine.succeed(browser + "state"))
    def browser_key(*keys):
        native_key(*keys)
        return browser_state()
    machine.succeed(browser + "prepare")
    observed = browser_key("LEFTCTRL", "A")
    assert (observed["start"], observed["end"]) == (0, 0), observed
    machine.succeed(browser + "prepare")
    observed = browser_key("LEFTMETA", "A")
    assert (observed["start"], observed["end"]) == (0, 10), observed
    browser_key("LEFTMETA", "C")
    assert machine.succeed(user("env", wayland, "${pkgs.wl-clipboard}/bin/wl-paste", "--no-newline")) == "alpha beta"
    observed = browser_key("LEFTMETA", "T")
    assert observed["tabs"] == 2, observed
    observed = browser_key("LEFTMETA", "W")
    assert observed["tabs"] == 1, observed
    machine.succeed(browser + "prepare")
    observed = browser_key("LEFTALT", "LEFT")
    assert (observed["start"], observed["end"]) == (6, 6), observed
    machine.succeed(browser + "close")

    machine.succeed(user("env", wayland, "${pkgs.uwsm}/bin/uwsm", "app", "-t", "service", "--",
                         "${pkgs.kdePackages.dolphin}/bin/dolphin", "--new-window", "/tmp"))
    machine.wait_until_succeeds(ox("window", "focus", "match", "--app-id", "^org.kde.dolphin$"), timeout=timedelta(seconds=30))
    for keys in [("LEFTMETA", "L"), ("END",), ("LEFTMETA", "A"), ("LEFTMETA", "C")]:
        native_key(*keys)
    assert machine.succeed(user("env", wayland, "${pkgs.wl-clipboard}/bin/wl-paste", "--no-newline")).rstrip("/") == "/tmp"
    native_key("LEFTMETA", "Q")
    machine.wait_until_fails(ox("window", "focus", "match", "--app-id", "^org.kde.dolphin$"), timeout=timedelta(seconds=10))

    machine.succeed(user("systemd-run", "--user", "--unit=mac-input-ghostty", "--collect", "--setenv=GSK_RENDERER=cairo", "--",
                         "${pkgs.ghostty}/bin/ghostty", "--config-default-files=false",
                         "--config-file=${
                           home.xdg.configFile."ghostty/config".source
                         }", "-e", "${python}/bin/python", "-c",
                         "import signal; print('GHOSTTY_CLIPBOARD_SENTINEL', flush=True); signal.pause()"))
    machine.wait_until_succeeds(ox("window", "focus", "match", "--app-id", "^com.mitchellh.ghostty$"), timeout=timedelta(seconds=30))
    for keys in [("LEFTMETA", "A"), ("LEFTMETA", "C")]:
        machine.succeed("${python}/bin/python /etc/mac-input-events.py chord " + " ".join(keys))
    assert "GHOSTTY_CLIPBOARD_SENTINEL" in machine.succeed(user("env", wayland, "${pkgs.wl-clipboard}/bin/wl-paste", "--no-newline"))
    machine.succeed("${python}/bin/python /etc/mac-input-events.py chord LEFTCTRL C")
    machine.wait_until_fails(user("systemctl", "--user", "is-active", "mac-input-ghostty.service"), timeout=timedelta(seconds=10))
    machine.wait_until_succeeds(ox("window", "focus", "match", "--app-id", "^wev$"))
    chord(False, caps=True)
    chord(True)

    # These are real logind sessions and a real VT switch, entirely in the VM.
    # The foreign-toplevel bridge remains alive with its old focused app.
    machine.succeed("systemctl start getty@tty2.service")
    machine.succeed("chvt 2")
    wait_session("tty")
    chord(False)
    machine.succeed("chvt 1")
    wait_session("wayland")
    chord(True)

    machine.succeed(user("systemctl", "--user", "stop", "desktop-input-bridge.service"))
    chord(False)
    machine.succeed(user("systemctl", "--user", "start", "desktop-input-bridge.service"))
    chord(True)

    # Waylock uses the actual session-lock protocol. Do not manufacture a
    # LockedHint: lost GUI focus must also stop remapping by itself.
    machine.succeed(user("systemd-run", "--user", "--unit=mac-input-lock", "--collect", "--",
                         "${pkgs.waylock}/bin/waylock"))
    machine.wait_for_console_text("session locked", timeout=timedelta(seconds=10))
    print("Native lock session metadata:", state())
    chord(False)
    machine.succeed(user("systemctl", "--user", "is-active", "desktop-input-bridge.service"))
    print("Actual Mac profile, nonroot service, PAM/VT and Waylock isolation passed")
  '';
}
