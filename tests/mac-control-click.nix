{
  pkgs,
  homeConfiguration,
  enableControlClick ? true,
  river ? homeConfiguration.config.jd.graphical.wayland.river.package,
}:
let
  python = pkgs.python3.withPackages (p: [ p.pygobject3 ]);
  gtkProbe = pkgs.stdenvNoCC.mkDerivation {
    name = "control-click-native-gtk-probe";
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.wrapGAppsHook3
      pkgs.gobject-introspection
    ];
    buildInputs = [ pkgs.gtk3 ];
    installPhase = ''
      install -Dm755 ${
        pkgs.writeText "control-click-gtk-probe.py" (
          "#!${python}/bin/python3\n" + builtins.readFile ./control_click_gtk_probe.py
        )
      } "$out/bin/control-click-gtk-probe"
    '';
  };
  login = pkgs.writers.writePython3Bin "control-click-test-login" { flakeIgnore = [ "E501" ]; } ''
    import os
    from pathlib import Path

    os.environ.update({
        "WLR_BACKENDS": "drm,libinput",
        "WLR_RENDERER": "pixman",
        "LIBSEAT_BACKEND": "logind",
    })
    executable = "${river}/bin/river"
    arguments = [executable, "-no-xwayland", "-c", "${pkgs.oxbow}/bin/oxbow"]
    if ${
      if enableControlClick then "True" else "False"
    } and not Path("/var/lib/control-click-disabled").exists():
        arguments.append("-control-click")
    os.execv(executable, arguments)
  '';
  client = pkgs.writers.writePython3Bin "control-click-wev" { flakeIgnore = [ "E501" ]; } ''
    import os

    descriptor = os.open("/tmp/control-click-wev.log", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.dup2(descriptor, 1)
    os.dup2(descriptor, 2)
    os.close(descriptor)
    executable = "${pkgs.coreutils}/bin/stdbuf"
    os.execv(executable, [executable, "-oL", "${pkgs.wev}/bin/wev"])
  '';
in
pkgs.testers.runNixOSTest {
  name = "river-native-control-click";
  nodes.machine = {
    virtualisation = {
      memorySize = 1536;
      cores = 2;
      qemu.options = [ "-vga none -device virtio-gpu-pci" ];
    };
    hardware.graphics.enable = true;
    fonts.packages = [ pkgs.dejavu_fonts ];
    users.users.jd = {
      isNormalUser = true;
      uid = 1000;
      extraGroups = [ "video" ];
    };
    environment.etc."control-click-vm".text = "isolated native regression VM";
    environment.systemPackages = [
      pkgs.wev
      pkgs.wlr-randr
      pkgs.kbd
      pkgs.waylock
      pkgs.python3
    ];
    services.getty.autologinUser = "jd";
    security.pam.services.waylock = { };
    services.greetd = {
      enable = true;
      settings = {
        initial_session = {
          command = "${login}/bin/control-click-test-login";
          user = "jd";
        };
        default_session = {
          command = "${pkgs.greetd}/bin/agreety";
          user = "greeter";
        };
      };
    };
  };
  testScript = ''
    import json
    import re
    import shlex
    from datetime import timedelta
    from typing import Any, cast

    start_all()
    machine.wait_for_unit("greetd.service")
    machine.wait_for_file("/run/user/1000/wayland-1")
    def user(*arguments):
        return shlex.join(["runuser", "-u", "jd", "--", "env",
                           "XDG_RUNTIME_DIR=/run/user/1000", "WAYLAND_DISPLAY=wayland-1",
                           "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus", *arguments])
    def launch():
        machine.wait_for_unit("user@1000.service")
        machine.succeed(user("systemctl", "--user", "import-environment", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY"))
        machine.succeed(user("systemd-run", "--user", "--unit=control-click-wev", "--collect", "--",
                             "${client}/bin/control-click-wev"))
        machine.wait_for_file("/tmp/control-click-wev.log")
        machine.wait_until_succeeds(user("${pkgs.oxbow}/bin/oxctl", "window", "focus", "match", "--app-id", "^wev$"), timeout=timedelta(seconds=20))
    def text():
        return machine.succeed("cat /tmp/control-click-wev.log")
    def qmp(events):
        assert machine.qmp_client is not None
        cast(Any, machine.qmp_client).send("input-send-event", {"events": events})
        machine.sleep(timedelta(milliseconds=75))
    def key(name, down):
        qmp([{"type": "key", "data": {"down": down, "key": {"type": "qcode", "data": name}}}])
    def button(name, down):
        qmp([{"type": "btn", "data": {"button": name, "down": down}}])
    def click(name="left"):
        button(name, True)
        button(name, False)
    def move():
        qmp([{"type": "abs", "data": {"axis": "x", "value": 16384}},
             {"type": "abs", "data": {"axis": "y", "value": 16384}}])
    def events_since(offset):
        # wev retains its old wl_pointer when devices return after a VT switch,
        # then binds another. Both objects receive the same protocol serial.
        events = re.findall(r"button: serial: (\d+); time: (\d+); button: (\d+) .*?state: (\d+)", text()[offset:])
        return [(int(button), int(state)) for _serial, _time, button, state in dict.fromkeys(events)]
    def check(sequence, expected):
        offset = len(text())
        sequence()
        observed = events_since(offset)
        assert observed == expected, (observed, expected, text()[offset:])

    launch()
    move()
    check(lambda: click(), [(272, 1), (272, 0)])
    check(lambda: click("right"), [(273, 1), (273, 0)])
    for control in ("ctrl", "ctrl_r"):
        key(control, True)
        check(lambda: click(), [(273, 1), (273, 0)])
        key(control, False)
    key("ctrl", True)
    check(lambda: (button("left", True), key("ctrl", False), button("left", False)), [(273, 1), (273, 0)])
    for release_order in (("left", "right"), ("right", "left")):
        key("ctrl", True)
        check(lambda: (button("left", True), button("right", True),
                       button(release_order[0], False), button(release_order[1], False)), [(273, 1), (273, 0)])
        key("ctrl", False)
    check(lambda: click(), [(272, 1), (272, 0)])
    # Control remains an ordinary keyboard modifier before/after the mouse chord.
    offset = len(text())
    key("ctrl", True)
    click()
    key("a", True)
    key("a", False)
    key("ctrl", False)
    key("b", True)
    key("b", False)
    keyboard = text()[offset:]
    assert re.search(r"sym: +a\b", keyboard) and re.search(r"sym: +b\b", keyboard), keyboard
    assert "Control" in keyboard, keyboard
    print("PASS: paired secondary clicks, both Controls, overlapping buttons and preserved keyboard events")

    # Real VT switching: no pointer events may escape into the inactive GUI.
    machine.succeed("systemctl start getty@tty2.service")
    machine.succeed("chvt 2")
    # logind/libinput device suspension and resumption are asynchronous to chvt.
    machine.sleep(timedelta(seconds=1))
    offset = len(text())
    key("ctrl", True)
    click()
    key("ctrl", False)
    assert events_since(offset) == [], text()[offset:]
    machine.succeed("chvt 1")
    machine.sleep(timedelta(seconds=1))
    move()
    offset = len(text())
    click()
    print("Post-VT pointer focus synchronization click:", events_since(offset))
    key("ctrl", True)
    check(lambda: click(), [(273, 1), (273, 0)])
    key("ctrl", False)

    # A genuine GTK application opens an actual native context menu.
    machine.succeed(user("systemctl", "--user", "stop", "control-click-wev"))
    machine.succeed(user("systemd-run", "--user", "--unit=control-click-gtk", "--collect", "--",
                         "${gtkProbe}/bin/control-click-gtk-probe"))
    machine.wait_for_file("/tmp/control-click-gtk-ready", timeout=timedelta(seconds=15))
    machine.wait_until_succeeds(user("${pkgs.oxbow}/bin/oxctl", "window", "focus", "match", "--app-id", "control-click-probe"), timeout=timedelta(seconds=20))
    move()
    key("ctrl", True)
    click()
    key("ctrl", False)
    machine.wait_for_file("/tmp/control-click-native-menu", timeout=timedelta(seconds=15))
    observed = json.loads(machine.succeed("tail -n1 /tmp/control-click-gtk.jsonl"))
    assert observed["button"] == 3, observed
    print("PASS: Control+primary opens a native GTK context menu without fake keyboard events")
    machine.succeed(user("systemctl", "--user", "stop", "control-click-gtk"))

    # Actual session lock: the lock client's pointer events retain primary click.
    machine.succeed(user("systemd-run", "--user", "--unit=control-click-lock", "--collect",
                         "--setenv=WAYLAND_DEBUG=client", "--", "${pkgs.waylock}/bin/waylock"))
    machine.wait_for_console_text("locked()", timeout=timedelta(seconds=15))
    move()
    key("ctrl", True)
    click()
    key("ctrl", False)
    lock_log = machine.succeed("journalctl _SYSTEMD_USER_UNIT=control-click-lock.service -o cat --no-pager")
    lock_buttons = re.findall(r"wl_pointer[#@]\d+\.button\(\d+,\s*\d+,\s*(\d+),\s*(\d+)\)", lock_log)
    assert lock_buttons[-2:] == [("272", "1"), ("272", "0")], lock_log
    print("PASS: Control+primary is not remapped in the real lock surface")

    # Same executable, opt-out on the next compositor start: Windows behavior.
    machine.succeed("touch /var/lib/control-click-disabled")
    # Greetd intentionally runs initial_session once per boot. Reboot only
    # this disposable VM to exercise a genuine new compositor session.
    machine.shutdown()
    machine.start()
    machine.wait_for_unit("greetd.service")
    machine.wait_for_file("/run/user/1000/wayland-1")
    launch()
    move()
    key("ctrl", True)
    check(lambda: click(), [(272, 1), (272, 0)])
    key("ctrl", False)
    print("PASS: opt-out retains Control+primary without translation")
  '';
}
