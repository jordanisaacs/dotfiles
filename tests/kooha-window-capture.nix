{ pkgs }:
let
  inherit (pkgs) lib;
  chooserConfig = pkgs.writeText "capture-default-chooser" "[screencast]\n";
  base = import ./kooha-capture.nix { inherit pkgs chooserConfig; };
in
base.extend {
  modules = [
    {
      name = lib.mkForce "kooha-native-window-chooser";
      nodes.machine = {
        environment = {
          systemPackages = [ pkgs.wtype ];
          etc."dconf/profile/kooha-capture".text = "user-db:user\n";
        };
        # The NixOS fixture lacks UWSM's imported home-profile PATH. Provide
        # the same chooser programs that the real session already resolves.
        systemd.user.services.xdg-desktop-portal-wlr = {
          path = [
            pkgs.fuzzel
            pkgs.slurp
          ];
          # Recreate a remembered monitor in this disposable VM. The backend
          # returns restore data only for monitor sources, not windows.
          environment.XDPW_PERSIST_MODE = "permanent";
        };
      };
      testScript = lib.mkForce ''
        import json
        import shlex
        from datetime import timedelta

        def user(*arguments):
            return shlex.join(["runuser", "-u", "alice", "--", "env",
                "XDG_RUNTIME_DIR=/run/user/1000", "DCONF_PROFILE=/etc/dconf/profile/kooha-capture",
                "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus",
                "WAYLAND_DISPLAY=wayland-1", "XDG_CURRENT_DESKTOP=river",
                "XDG_SESSION_TYPE=wayland", "GDK_BACKEND=wayland", *arguments])

        def rows():
            return json.loads(machine.succeed(user("kooha-accessibility")))

        def wait_button(name):
            for attempt in range(40):
                tree = rows()
                if any(row["name"] == name and row["role"] == "button" and row["sensitive"] for row in tree):
                    return
                machine.sleep(duration=timedelta(milliseconds=250))
            raise AssertionError(tree)

        def wait_chooser():
            machine.wait_until_succeeds("pgrep -x fuzzel", timeout=timedelta(seconds=20))
            machine.sleep(duration=timedelta(milliseconds=300))

        def cancel_chooser():
            machine.succeed(user("wtype", "-k", "Escape"))
            machine.wait_until_fails("pgrep -x fuzzel", timeout=timedelta(seconds=10))
            wait_button("Record")

        def recordings():
            return machine.succeed("find /home/alice -name '*.webm'").splitlines()

        machine.wait_for_unit("greetd.service")
        machine.wait_for_file("/run/user/1000/wayland-1")
        machine.wait_until_succeeds(user("oxctl", "window", "list", "--json"))
        output = json.loads(machine.succeed(user("wlr-randr", "--json")))[0]["name"]
        machine.succeed(user("wlr-randr", "--output", output, "--custom-mode", "2256x1504@60Hz", "--scale", "1.25"))
        machine.succeed(user("systemctl", "--user", "import-environment", "WAYLAND_DISPLAY", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE"))
        machine.succeed(user("systemctl", "--user", "start", "kooha-test-session.target"))
        machine.succeed(user("systemctl", "--user", "start", "pipewire.service", "wireplumber.service", "xdg-desktop-portal.service"))
        schema = "${pkgs.kooha}/share/gsettings-schemas/kooha-${pkgs.kooha.version}/glib-2.0/schemas"
        machine.succeed(user("gsettings", "--schemadir", schema, "set", "io.github.seadve.Kooha", "capture-mode", "monitor-window"))
        machine.succeed(user("gsettings", "--schemadir", schema, "set", "io.github.seadve.Kooha", "record-desktop-audio", "false"))
        machine.succeed(user("systemd-run", "--user", "--unit=app-kooha-motion-fixture", "--setenv=WAYLAND_DISPLAY=wayland-1", "kooha-motion-fixture", "--fixed-size"))
        machine.succeed(user("systemd-run", "--user", "--unit=app-river-io.github.seadve.Kooha@window-fixture", "--setenv=WAYLAND_DISPLAY=wayland-1", "--setenv=XDG_CURRENT_DESKTOP=river", "--setenv=XDG_SESSION_TYPE=wayland", "--setenv=GTK_A11Y=atspi", "--setenv=DCONF_PROFILE=/etc/dconf/profile/kooha-capture", "--setenv=KOOHA_EXPERIMENTAL=all", "--setenv=RUST_LOG=kooha=debug", "${pkgs.kooha}/bin/kooha"))
        machine.wait_until_succeeds(user("kooha-accessibility", "Capture a Monitor or Window"), timeout=timedelta(seconds=20))
        wait_button("Record")

        # Escape cancels the actual Fuzzel portal chooser without writing video.
        machine.succeed(user("kooha-accessibility", "Record"))
        wait_chooser()
        cancel_chooser()
        assert recordings() == [], recordings()

        # Recreate the remembered-monitor state, then clear it through the UI.
        machine.succeed(user("kooha-accessibility", "Record"))
        wait_chooser()
        machine.succeed(user("wtype", "-d", "20", "Monitor: " + output, "-k", "Return"))
        machine.wait_until_fails("pgrep -x fuzzel", timeout=timedelta(seconds=10))
        wait_button("Stop")
        machine.sleep(duration=timedelta(seconds=3))
        machine.succeed(user("kooha-accessibility", "Stop"))
        wait_button("Record")
        monitor_files = recordings()
        assert len(monitor_files) == 1, monitor_files
        token = machine.succeed(user("gsettings", "--schemadir", schema, "get", "io.github.seadve.Kooha", "screencast-restore-token")).strip()
        assert token.startswith(chr(39)) and token.endswith(chr(39)) and token.strip(chr(39)), token
        machine.succeed(user("kooha-accessibility", "Forget Previously Selected Video Sources"))
        for attempt in range(40):
            cleared = machine.succeed(user("gsettings", "--schemadir", schema, "get", "io.github.seadve.Kooha", "screencast-restore-token")).strip()
            if cleared == chr(39) * 2:
                break
            machine.sleep(duration=timedelta(milliseconds=100))
        else:
            raise AssertionError(cleared)

        # Type a real Window-row label and accept it through native Wayland input.
        portal_before_window = machine.succeed(user("journalctl", "--user", "-b", "-u", "xdg-desktop-portal-wlr", "--no-pager"))
        machine.succeed(user("kooha-accessibility", "Record"))
        wait_chooser()
        machine.succeed(user("wtype", "-d", "20", "Window: Capture motion fixture", "-k", "Return"))
        machine.wait_until_fails("pgrep -x fuzzel", timeout=timedelta(seconds=10))
        wait_button("Stop")
        machine.sleep(duration=timedelta(seconds=5))
        portal_recording = machine.succeed(user("journalctl", "--user", "-b", "-u", "xdg-desktop-portal-wlr", "--no-pager"))
        assert portal_recording.count("out of buffers") == portal_before_window.count("out of buffers"), portal_recording
        machine.succeed(user("kooha-accessibility", "Stop"))
        wait_button("Record")
        files = recordings()
        window_files = list(set(files) - set(monitor_files))
        assert len(files) == 2 and len(window_files) == 1, files
        metadata = json.loads(machine.succeed(shlex.join(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-show_entries", "stream=width,height", "-of", "json", window_files[0]])))
        video = metadata["streams"][0]
        assert 0 < video["width"] < 2256 and 0 < video["height"] < 1504, metadata
        assert float(metadata["format"]["duration"]) >= 3, metadata
        frames = machine.succeed(shlex.join(["ffmpeg", "-v", "error", "-i", window_files[0], "-vf", "fps=2,scale=16:16", "-f", "framemd5", "-"]))
        hashes = {line.rsplit(",", 1)[-1].strip() for line in frames.splitlines() if line and not line.startswith("#")}
        assert len(hashes) >= 3, frames
        machine.succeed(user("kooha-accessibility", "Record"))
        wait_chooser()
        cancel_chooser()
        assert recordings() == files, recordings()
        diagnostics = machine.succeed(user("journalctl", "--user", "-b", "-u", "app-river-io.github.seadve.Kooha@window-fixture.service", "--no-pager"))
        assert "MONITOR | WINDOW" in diagnostics, diagnostics
        assert "is_multiple_sources=true" in diagnostics, diagnostics
        portal_log = machine.succeed(user("journalctl", "--user", "-b", "-u", "xdg-desktop-portal-wlr", "--no-pager"))
        # Monitor encoder drain may briefly exhaust its producer buffers.
        # Preserve/count that diagnostic; the window's recording phase above
        # must deliver live frames without new starvation warnings.
        print("Capture/drain buffer warnings:", portal_log.count("out of buffers"))
        assert machine.succeed(user("systemctl", "--user", "show", "xdg-desktop-portal-wlr.service", "-p", "NRestarts", "--value")).strip() == "0", portal_log
        compositor_log = machine.succeed("cat /tmp/kooha-river.log")
        assert "initializing river version" in compositor_log, compositor_log
        assert "Atomic commit failed" not in compositor_log, compositor_log
        print(metadata)
        machine.succeed(user("systemctl", "--user", "stop", "app-river-io.github.seadve.Kooha@window-fixture.service", "app-kooha-motion-fixture.service"))
      '';
    }
  ];
}
