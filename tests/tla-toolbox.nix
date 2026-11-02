{
  pkgs,
  withFix ? true,
}:
let
  toolbox = if withFix then pkgs.tlaplus-toolbox else pkgs.tlaplus-toolbox.unwrapped;
  manifest = pkgs.writeText "toolbox-probe-manifest" ''
    Premain-Class: SwtToolboxProbe
  '';
  probe = pkgs.runCommand "toolbox-native-probe.jar" { nativeBuildInputs = [ pkgs.jdk21 ]; } ''
    mkdir classes
    cp ${./SwtToolboxProbe.java} SwtToolboxProbe.java
    javac --release 11 -d classes SwtToolboxProbe.java
    jar cfm "$out" ${manifest} -C classes .
  '';
  browser = pkgs.writers.writePython3Bin "toolbox-test-browser" { } ''
    import json
    import sys
    from pathlib import Path

    Path("/tmp/toolbox-browser.json").write_text(json.dumps(sys.argv[1:]))
  '';
  desktop = pkgs.writeText "toolbox-test-browser.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=Toolbox Test Browser
    Exec=${browser}/bin/toolbox-test-browser %u
    MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
    Terminal=false
  '';
  mimeapps = pkgs.writeText "toolbox-mimeapps.list" ''
    [Default Applications]
    text/html=toolbox-test-browser.desktop
    x-scheme-handler/http=toolbox-test-browser.desktop
    x-scheme-handler/https=toolbox-test-browser.desktop
  '';
  emptyBrowsers = pkgs.writeText "toolbox-empty-browser.prefs" ''
    eclipse.preferences.version=1
    browsers=<?xml version\="1.0" encoding\="UTF-8"?>\n<web-browsers current\="-1"/>
  '';
  gtkSettings = pkgs.writeText "toolbox-gtk-settings.ini" ''
    [Settings]
    gtk-font-name=Noto Sans 15
  '';
  softwareXwayland = pkgs.writers.writePython3Bin "toolbox-test-xwayland" { } ''
    import os
    import sys

    executable = (
        "${pkgs.xwayland}"
        "/bin/Xwayland"
    )
    os.execv(executable, [executable, "-glamor", "off", *sys.argv[1:]])
  '';
  login = pkgs.writers.writePython3Bin "toolbox-test-login" { } ''
    import os

    os.environ.update({
        "WLR_BACKENDS": "headless",
        "WLR_RENDERER": "pixman",
        "WLR_HEADLESS_OUTPUTS": "1",
        "WLR_XWAYLAND": (
            "${softwareXwayland}"
            "/bin/toolbox-test-xwayland"
        ),
    })
    executable = (
        "${pkgs.river-reka}"
        "/bin/river"
    )
    manager = (
        "${pkgs.oxbow}"
        "/bin/oxbow"
    )
    os.execv(executable, [executable, "-c", manager])
  '';
in
pkgs.testers.runNixOSTest {
  name = "toolbox-native-rendering-and-browser";
  nodes.machine = {
    virtualisation = {
      memorySize = 2048;
      cores = 2;
    };
    boot.kernelPackages = pkgs.linuxPackages_latest;
    fonts.packages = [ pkgs.noto-fonts ];
    environment.systemPackages = [ pkgs.shared-mime-info ];
    users.users.alice = {
      isNormalUser = true;
      uid = 1000;
    };
    services.greetd = {
      enable = true;
      settings = {
        initial_session = {
          user = "alice";
          command = "${login}/bin/toolbox-test-login";
        };
        default_session.command = "${pkgs.coreutils}/bin/sleep infinity";
      };
    };
    systemd.tmpfiles.rules = [
      "d /home/alice/.config 0755 alice users -"
      "d /home/alice/.config/gtk-3.0 0755 alice users -"
      "d /home/alice/.local 0755 alice users -"
      "d /home/alice/.local/share 0755 alice users -"
      "d /home/alice/.local/share/applications 0755 alice users -"
      "L+ /home/alice/.config/mimeapps.list - - - - ${mimeapps}"
      "L+ /home/alice/.config/gtk-3.0/settings.ini - - - - ${gtkSettings}"
      "L+ /home/alice/.local/share/applications/toolbox-test-browser.desktop - - - - ${desktop}"
    ];
  };
  testScript = ''
    from datetime import timedelta
    import json
    import shlex

    runtime = "/run/user/1000"
    def user(*arguments):
        return shlex.join([
            "runuser", "-u", "alice", "--", "env",
            "HOME=/home/alice", "XDG_CONFIG_HOME=/home/alice/.config",
            "XDG_DATA_HOME=/home/alice/.local/share",
            "XDG_RUNTIME_DIR=" + runtime,
            "DBUS_SESSION_BUS_ADDRESS=unix:path=" + runtime + "/bus",
            "WAYLAND_DISPLAY=wayland-1", "DISPLAY=:0",
            *arguments,
        ])

    machine.wait_for_unit("greetd.service")
    machine.wait_for_file(runtime + "/oxbow-wayland-1.sock")
    machine.succeed(user("${pkgs.wlr-randr}/bin/wlr-randr",
        "--output", "HEADLESS-1", "--scale", "1.25"))
    machine.succeed("chown -R alice:users /home/alice")
    machine.succeed(user("${pkgs.desktop-file-utils}/bin/update-desktop-database", "-v",
        "/home/alice/.local/share/applications"))
    discovery = machine.succeed(user("${pkgs.glib.bin}/bin/gio", "mime", "text/html"))
    print(discovery)
    assert "toolbox-test-browser.desktop" in discovery, discovery
    # Match the empty browser list Eclipse saved after its failed discovery.
    # The repaired native MIME lookup must recover the system browser itself.
    preferences = "/home/alice/test-workspace/.metadata/.plugins/org.eclipse.core.runtime/.settings"
    machine.succeed(user("mkdir", "-p", preferences))
    machine.succeed("cp ${emptyBrowsers} " + preferences + "/org.eclipse.ui.browser.prefs")
    machine.succeed("chown -R alice:users /home/alice/test-workspace")
    url = "https://toolbox-audit.invalid/probe?x=a%20b&y=1"
    # Preload only in this instrumented test: the agent must not alter native
    # library initialization relative to an ordinary Eclipse launcher startup.
    command = user("env", "GDK_BACKEND=wayland",
        "LD_PRELOAD=${pkgs.gtk3}/lib/libgtk-3.so.0",
        "${toolbox}/bin/tla-toolbox", "-data", "/home/alice/test-workspace",
        "-configuration", "/home/alice/test-configuration",
        "--launcher.suppressErrors", "-vmargs",
        "-javaagent:${probe}=/tmp/toolbox-result.json", "-Xmx384m",
        "-Dorg.eclipse.equinox.http.jetty.http.port=0", "-Dtoolbox.test.url=" + url)
    print(machine.succeed(command, timeout=timedelta(seconds=90)))
    result = json.loads(machine.succeed("cat /tmp/toolbox-result.json"))
    assert result["labelHeight"] >= result["fontHeight"], result
    assert result["systemBrowser"], result
    machine.wait_for_file("/tmp/toolbox-browser.json")
    assert json.loads(machine.succeed("cat /tmp/toolbox-browser.json")) == [url]
    print("Native Toolbox widget geometry and Eclipse default-browser dispatch:", result)
  '';
}
