{
  pkgs,
  drm ? false,
  chooserConfig ? pkgs.writeText "capture-test-chooser" "[screencast]\nchooser_type=none\n",
}:
let
  python = pkgs.python3.withPackages (p: [
    p.pygobject3
    p.pycairo
  ]);
  accessibility = pkgs.stdenvNoCC.mkDerivation {
    pname = "kooha-accessibility";
    version = "1";
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.wrapGAppsHook4
      pkgs.gobject-introspection
    ];
    buildInputs = [
      pkgs.gtk4
      pkgs.at-spi2-core
    ];
    installPhase = ''
      install -Dm755 ${./kooha_motion_fixture.py} "$out/bin/kooha-motion-fixture"
      substituteInPlace "$out/bin/kooha-motion-fixture" \
        --replace-fail '#!/usr/bin/env python3' '#!${python}/bin/python3'
      install -Dm755 ${./kooha_accessibility.py} "$out/bin/kooha-accessibility"
      substituteInPlace "$out/bin/kooha-accessibility" \
        --replace-fail '#!/usr/bin/env python3' '#!${python}/bin/python3'
    '';
  };
  login = pkgs.writers.writePython3Bin "kooha-test-login" { flakeIgnore = [ "E501" ]; } ''
    import os
    import subprocess

    os.environ.update({
        "WLR_BACKENDS": "${if drm then "drm,libinput" else "headless"}",
        "LIBSEAT_BACKEND": "logind",
        "WLR_RENDERER": "pixman",
        "WLR_HEADLESS_OUTPUTS": "1",
        "XDG_SESSION_TYPE": "wayland",
        "XDG_CURRENT_DESKTOP": "river",
        "GDK_BACKEND": "wayland",
    })
    subprocess.run(["${pkgs.systemd}/bin/systemctl", "--user", "import-environment", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE"], check=True)
    # greetd may attach stderr to the virtual terminal instead of journald.
    # Preserve the real compositor diagnostics in this disposable VM.
    with open("/tmp/kooha-river.log", "w") as diagnostics:
        os.dup2(diagnostics.fileno(), 2)
    executable = "${pkgs.river-reka-with-health}/bin/river"
    os.execv(executable, [executable, "-no-xwayland", "-c", "${pkgs.oxbow}/bin/oxbow"])
  '';
in
pkgs.testers.runNixOSTest {
  name = "kooha-native-capture${pkgs.lib.optionalString drm "-drm"}";
  nodes.machine = {
    boot.kernelPackages = pkgs.lib.mkIf drm pkgs.linuxPackages_latest;
    virtualisation = {
      memorySize = 2048;
      cores = 2;
      qemu.options = pkgs.lib.optionals drm [ "-vga none -device virtio-gpu-pci" ];
    };
    hardware.graphics.enable = true;
    security.rtkit.enable = true;
    programs.dconf.enable = true;
    services = {
      pipewire = {
        enable = true;
        package = pkgs.pipewire-capture or pkgs.pipewire;
        pulse.enable = true;
      };
      dbus.implementation = "broker";
      gnome.at-spi2-core.enable = true;
      greetd = {
        enable = true;
        settings = {
          initial_session = {
            user = "alice";
            command = "${login}/bin/kooha-test-login";
          };
          default_session.command = "${pkgs.coreutils}/bin/sleep infinity";
        };
      };
    };
    xdg.portal = {
      enable = true;
      wlr.enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      config.river.default = [
        "wlr"
        "gtk"
      ];
    };
    fonts.packages = [ pkgs.noto-fonts ];
    users.users.alice = {
      isNormalUser = true;
      uid = 1000;
      linger = true;
      extraGroups = pkgs.lib.optionals drm [
        "video"
        "input"
      ];
    };
    environment.systemPackages = [
      pkgs.kooha
      pkgs.ffmpeg-headless
      pkgs.wlr-randr
      pkgs.oxbow
      pkgs.glib.bin
      pkgs.at-spi2-core
      python
      accessibility
    ];
    systemd = {
      user = {
        services = {
          xdg-desktop-portal-wlr.serviceConfig.ExecStart = pkgs.lib.mkForce [
            ""
            "${pkgs.xdg-desktop-portal-wlr}/libexec/xdg-desktop-portal-wlr -l DEBUG"
          ];
          xdg-desktop-portal.environment.G_MESSAGES_DEBUG = "all";
        };
        targets.kooha-test-session.requires = [ "graphical-session.target" ];
      };
      tmpfiles.rules = [
        "d /home/alice/.config 0755 alice users -"
        "d /home/alice/.config/xdg-desktop-portal-wlr 0755 alice users -"
        "L+ /home/alice/.config/xdg-desktop-portal-wlr/config - - - - ${chooserConfig}"
        "d /home/alice/.config/gtk-4.0 0755 alice users -"
        "L+ /home/alice/.config/gtk-4.0/settings.ini - - - - ${pkgs.writeText "capture-test-gtk" ''
          [Settings]
          gtk-font-name=Noto Sans 15
          gtk-application-prefer-dark-theme=1
        ''}"
      ];
    };
  };
  testScript = ''
    import json
    import shlex
    from datetime import timedelta

    def user(*arguments):
        return shlex.join(["runuser", "-u", "alice", "--", "env",
            "XDG_RUNTIME_DIR=/run/user/1000",
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus",
            "WAYLAND_DISPLAY=wayland-1", "XDG_CURRENT_DESKTOP=river",
            "XDG_SESSION_TYPE=wayland", "GDK_BACKEND=wayland", *arguments])

    machine.wait_for_unit("greetd.service")
    machine.wait_for_file("/run/user/1000/wayland-1")
    machine.wait_until_succeeds(user("oxctl", "window", "list", "--json"))
    outputs = json.loads(machine.succeed(user("wlr-randr", "--json")))
    assert len(outputs) == 1, outputs
    output_name = outputs[0]["name"]
    ${pkgs.lib.optionalString drm ''
      assert not output_name.startswith("HEADLESS"), outputs
      machine.wait_for_file("/dev/dri/card0")
    ''}
    machine.succeed(user("wlr-randr", "--output", output_name, "--custom-mode", "2256x1504@60Hz", "--scale", "1.25"))
    machine.succeed(user("systemctl", "--user", "import-environment", "WAYLAND_DISPLAY", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE"))
    machine.succeed(user("systemctl", "--user", "start", "kooha-test-session.target"))
    machine.succeed(user("systemctl", "--user", "start", "pipewire.service", "wireplumber.service", "xdg-desktop-portal.service"))
    schema = "${pkgs.kooha}/share/gsettings-schemas/kooha-${pkgs.kooha.version}/glib-2.0/schemas"
    machine.succeed(user("gsettings", "--schemadir", schema, "set", "io.github.seadve.Kooha", "capture-mode", "selection"))
    machine.succeed(user("gsettings", "--schemadir", schema, "set", "io.github.seadve.Kooha", "record-desktop-audio", "false"))
    machine.succeed(user("systemd-run", "--user", "--unit=app-kooha-fixture", "--setenv=WAYLAND_DISPLAY=wayland-1", "--setenv=XDG_CURRENT_DESKTOP=river", "--setenv=XDG_SESSION_TYPE=wayland", "--setenv=GTK_A11Y=atspi", "--setenv=RUST_LOG=kooha=debug", "--setenv=GST_DEBUG=3", "${pkgs.kooha}/bin/kooha"))
    machine.wait_until_succeeds(user("kooha-accessibility", "Capture a Selection of Screen"), timeout=timedelta(seconds=20))
    for attempt in range(3):
        machine.succeed(user("kooha-accessibility", "Record"))
        machine.sleep(duration=timedelta(seconds=5))
        diagnostics = machine.succeed(user("journalctl", "--user", "-b", "-u", "app-kooha-fixture.service", "--no-pager"))
        rows = json.loads(machine.succeed(user("kooha-accessibility")))
        assert any(row["name"] == "Select Area" for row in rows), rows
        assert diagnostics.count("Pipeline changed state from `Paused` -> `Playing`") >= attempt + 1, diagnostics
        assert not any(row["name"] == "Loading…" for row in rows), rows
        machine.succeed(user("kooha-accessibility", "Cancel"))
        machine.sleep(duration=timedelta(seconds=1))
        rows = json.loads(machine.succeed(user("kooha-accessibility")))
        assert not any(row["name"] == "Select Area" for row in rows), rows
        assert any(row["name"] == "Record" and row["role"] == "button" and row["sensitive"] for row in rows), rows

    # All capture and input below stays inside this disposable VM.
    machine.succeed(user("systemd-run", "--user", "--unit=app-kooha-motion-fixture", "--setenv=WAYLAND_DISPLAY=wayland-1", "kooha-motion-fixture"))
    machine.succeed(user("kooha-accessibility", "Capture a Monitor or Window"))
    machine.succeed(user("kooha-accessibility", "Record"))
    machine.sleep(duration=timedelta(seconds=5))
    machine.succeed(user("kooha-accessibility", "Stop"))
    machine.sleep(duration=timedelta(seconds=3))
    recording = machine.succeed("find /home/alice -name '*.webm'").strip()
    assert recording and "\n" not in recording, recording
    metadata = json.loads(machine.succeed(shlex.join(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-show_entries", "stream=width,height", "-of", "json", recording])))
    assert float(metadata["format"]["duration"]) >= 3, metadata
    assert metadata["streams"][0]["width"] == 2256, metadata
    assert metadata["streams"][0]["height"] == 1504, metadata
    frames = machine.succeed(shlex.join(["ffmpeg", "-v", "error", "-i", recording, "-vf", "fps=2,scale=16:16", "-f", "framemd5", "-"]))
    hashes = {line.rsplit(",", 1)[-1].strip() for line in frames.splitlines() if line and not line.startswith("#")}
    assert len(hashes) >= 3, frames
    portal_log = machine.succeed(user("journalctl", "--user", "-b", "-u", "xdg-desktop-portal-wlr", "--no-pager"))
    assert "out of buffers" not in portal_log, portal_log
    assert machine.succeed(user("systemctl", "--user", "show", "xdg-desktop-portal-wlr.service", "-p", "NRestarts", "--value")).strip() == "0", portal_log
    compositor_log = machine.succeed("cat /tmp/kooha-river.log")
    assert "initializing river version" in compositor_log, compositor_log
    assert "Atomic commit failed" not in compositor_log, compositor_log
    assert "output commit failed" not in compositor_log, compositor_log
    print(machine.succeed(user("oxctl", "window", "list", "--json")))
    machine.succeed(user("systemctl", "--user", "stop", "app-kooha-fixture.service", "app-kooha-motion-fixture.service"))
  '';
}
