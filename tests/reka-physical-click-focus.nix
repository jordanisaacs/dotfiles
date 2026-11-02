{ pkgs, homeConfiguration }:
let
  home = homeConfiguration.config;
  river = home.jd.graphical.wayland.river.package;
  sessionInitText = home.xdg.configFile."reka/init.el".text;
  firefox = home.programs.firefox.finalPackage;
  firefoxUserJS = home.home.file.".mozilla/firefox/personal/user.js".source;
  firefoxChrome = home.home.file.".mozilla/firefox/personal/chrome/userChrome.css".source;
  init = pkgs.writeText "reka-physical-init.el" (
    pkgs.lib.replaceStrings [ "(add-hook 'reka-ready-hook #'jd-reka-ready)" ] [ "" ] sessionInitText
  );
  manager = pkgs.writers.writePython3Bin "reka-physical-manager" { } ''
    import os

    log = os.open("/tmp/reka-manager.log", os.O_WRONLY | os.O_CREAT, 0o600)
    os.dup2(log, 1)
    os.dup2(log, 2)
    os.environ["RUST_LOG"] = "reka=debug"
    executable = (
        "${pkgs.reka-emacs}"
        "/bin/emacs"
    )
    init = "${init}"
    os.execv(executable, [executable, "-Q", "--load", init])
  '';
  starter = pkgs.writers.writePython3Bin "reka-test-start-manager" { } ''
    import os

    executable = (
        "${pkgs.systemd}"
        "/bin/systemctl"
    )
    os.execv(executable, [executable, "--user", "start", "focus-reka"])
  '';
  # The selected River package's store name can itself exceed 75 characters.
  login = pkgs.writers.writePython3Bin "reka-physical-login" { flakeIgnore = [ "E501" ]; } ''
    import os

    os.environ.update({
        "WLR_BACKENDS": "drm,libinput",
        "WLR_RENDERER": "pixman",
        "LIBSEAT_BACKEND": "logind",
    })
    executable = (
        "${river}"
        "/bin/river"
    )
    manager = (
        "${starter}"
        "/bin/reka-test-start-manager"
    )
    os.execv(executable, [executable, "-no-xwayland", "-c", manager])
  '';
  client = pkgs.writers.writePython3Bin "reka-physical-client" { } ''
    import os
    import sys

    log = os.open(
        "/tmp/reka-client-" + sys.argv[1] + ".log",
        os.O_WRONLY | os.O_CREAT, 0o600,
    )
    os.dup2(log, 1)
    os.dup2(log, 2)
    executable = (
        "${pkgs.coreutils}"
        "/bin/stdbuf"
    )
    client = (
        "${pkgs.wev}"
        "/bin/wev"
    )
    os.execv(executable, [executable, "-oL", client])
  '';
  browserProbe = pkgs.writers.writePython3Bin "reka-browser-probe" { } (
    builtins.readFile ./firefox_chrome_probe.py
  );
  receiver = pkgs.writers.writePython3 "reka-ghostty-receiver" { } (
    builtins.readFile ./ghostty_input_fixture.py
  );
in
pkgs.testers.runNixOSTest {
  name = "reka-physical-click-focus";
  nodes.machine = {
    virtualisation = {
      memorySize = 3072;
      cores = 2;
      qemu.options = [ "-vga none -device virtio-gpu-pci" ];
    };
    hardware.graphics.enable = true;
    fonts.packages = [
      pkgs.noto-fonts
      pkgs.dejavu_fonts
    ];
    users.users.jd = {
      isNormalUser = true;
      uid = 1000;
      extraGroups = [
        "video"
        "input"
      ];
    };
    systemd.user.services = {
      focus-reka = {
        environment = {
          WAYLAND_DISPLAY = "wayland-1";
        };
        serviceConfig = {
          ExecStart = "${manager}/bin/reka-physical-manager";
          TimeoutStopSec = 10;
        };
      };
      focus-oxbow = {
        environment = {
          WAYLAND_DISPLAY = "wayland-1";
        };
        serviceConfig.ExecStart = "${pkgs.oxbow}/bin/oxbow";
      };
    };
    services.greetd = {
      enable = true;
      settings = {
        initial_session = {
          command = "${login}/bin/reka-physical-login";
          user = "jd";
        };
        default_session = {
          command = "${pkgs.greetd}/bin/agreety";
          user = "greeter";
        };
      };
    };
    environment.systemPackages = [
      pkgs.reka-emacs
      pkgs.wlr-randr
      pkgs.wev
      pkgs.ghostty
      firefox
      pkgs.python3
    ];
  };
  testScript = ''
    from datetime import timedelta
    from typing import Any, cast
    import json
    import re
    import shlex


    def user(*args):
        return shlex.join(
            [
                "runuser",
                "-u",
                "jd",
                "--",
                "env",
                "XDG_RUNTIME_DIR=/run/user/1000",
                "WAYLAND_DISPLAY=wayland-1",
                *args,
            ]
        )


    def evaluate(form):
        return machine.succeed(
            user("emacsclient", "--socket-name", "reka", "--eval", form)
        ).strip()


    start_all()
    machine.wait_for_unit("greetd.service")
    machine.wait_for_file("/run/user/1000/wayland-1")
    machine.wait_until_succeeds(
        user(
            "emacsclient",
            "--socket-name",
            "reka",
            "--eval",
            '(unless reka-ready (error "not ready"))',
        )
    )
    for name in ("a", "b"):
        machine.succeed(
            user(
                "systemd-run",
                "--user",
                "--unit=reka-client-" + name,
                "--setenv=XDG_RUNTIME_DIR=/run/user/1000",
                "--setenv=WAYLAND_DISPLAY=wayland-1",
                "${client}/bin/reka-physical-client",
                name,
            )
        )
        machine.wait_for_file("/tmp/reka-client-" + name + ".log")
    machine.wait_until_succeeds(
        user(
            "emacsclient",
            "--socket-name",
            "reka",
            "--eval",
            '(unless (= 2 (length (reka--list-buffers))) (error "waiting"))',
        )
    )
    evaluate(
        "(progn (setq physical-a (aref (reka--list-buffers) 0) physical-b (aref (reka--list-buffers) 1)) (delete-other-windows) (switch-to-buffer physical-a) (set-window-buffer (split-window-right) physical-b) (redisplay t) t)"
    )
    machine.sleep(timedelta(milliseconds=300))
    outputs = json.loads(machine.succeed(user("wlr-randr", "--json")))
    output = outputs[0]
    mode = next(m for m in output["modes"] if m["current"])
    width = mode["width"] / output["scale"]
    height = mode["height"] / output["scale"]


    def click_at(x, y):
        assert machine.qmp_client is not None
        qmp = cast(Any, machine.qmp_client)
        qmp.send(
            "input-send-event",
            {
                "events": [
                    {
                        "type": "abs",
                        "data": {"axis": "x", "value": round(x / width * 32767)},
                    },
                    {
                        "type": "abs",
                        "data": {"axis": "y", "value": round(y / height * 32767)},
                    },
                ]
            },
        )
        qmp.send(
            "input-send-event",
            {"events": [{"type": "btn", "data": {"button": "left", "down": True}}]},
        )
        qmp.send(
            "input-send-event",
            {"events": [{"type": "btn", "data": {"button": "left", "down": False}}]},
        )


    def placement(buffer):
        return json.loads(
            json.loads(
                evaluate(
                    "(json-serialize (vconcat (buffer-local-value 'reka-floating-geometry "
                    + buffer
                    + ")))"
                )
            )
        )


    def click(buffer):
        # All geometry RPCs precede hardware clicks; none occur before typing.
        x, y, w, h = placement(buffer)
        click_at(x + w / 2, y + h / 2)


    try:
        click("physical-a")
        machine.send_key("x")
        machine.sleep(timedelta(milliseconds=200))
        click("physical-b")
        machine.send_key("y")
        machine.sleep(timedelta(milliseconds=200))
        logs = {
            name: machine.succeed("cat /tmp/reka-client-" + name + ".log")
            for name in ("a", "b")
        }
        print(logs)
        assert any(re.search(r"sym: +x\b", text) for text in logs.values()), logs
        assert any(re.search(r"sym: +y\b", text) for text in logs.values()), logs
        assert not any(
            re.search(r"sym: +x\b", text) and re.search(r"sym: +y\b", text)
            for text in logs.values()
        ), logs
        print(
            "PASS: emulated hardware clicks redirect emulated hardware typing between real clients"
        )
        machine.succeed(
            user("systemctl", "--user", "stop", "reka-client-a", "reka-client-b")
        )
        machine.wait_until_succeeds(
            user(
                "emacsclient",
                "--socket-name",
                "reka",
                "--eval",
                '(unless (= 0 (length (reka--list-buffers))) (error "Waiting for fixtures to close"))',
            )
        )
        candidate = next(
            (m for m in output["modes"] if m["width"] >= 1920 and m["width"] <= 2256), mode
        )
        machine.succeed(
            user(
                "wlr-randr",
                "--output",
                output["name"],
                "--mode",
                str(candidate["width"]) + "x" + str(candidate["height"]),
                "--scale",
                "1.25",
            )
        )
        width = candidate["width"] / 1.25
        height = candidate["height"] / 1.25
        machine.succeed(
            user(
                "${browserProbe}/bin/reka-browser-probe",
                "prepare",
                "/home/jd/firefox-fixture",
                "${firefoxUserJS}",
                "${firefoxChrome}",
            )
        )
        common = [
            "systemd-run",
            "--user",
            "--setenv=XDG_RUNTIME_DIR=/run/user/1000",
            "--setenv=WAYLAND_DISPLAY=wayland-1",
        ]
        machine.succeed(
            user(
                *common,
                "--unit=focus-ghostty",
                "${pkgs.ghostty}/bin/ghostty",
                "--config-default-files=false",
                "--gtk-single-instance=false",
                "--gtk-titlebar=false",
                "-e",
                "${receiver}",
            )
        )
        machine.wait_for_file("/tmp/reka-ghostty-input")
        machine.succeed(
            user(
                *common,
                "--unit=focus-firefox",
                "--setenv=MOZ_ENABLE_WAYLAND=1",
                "--setenv=MOZ_REMOTE_ALLOW_SYSTEM_ACCESS=1",
                "${firefox}/bin/firefox",
                "--no-remote",
                "--profile",
                "/home/jd/firefox-fixture",
                "--marionette",
                "about:blank",
            )
        )
        machine.wait_until_succeeds(
            user("${browserProbe}/bin/reka-browser-probe", "geometry")
        )
        buffers = "(append (reka--list-buffers) nil)"
        expression = (
            '(progn (setq physical-firefox (seq-find (lambda(b)(string-match-p "firefox" (or (buffer-local-value (quote reka-app-id) b) ""))) '
            + buffers
            + ") physical-ghostty (seq-find (lambda(b)(not (eq b physical-firefox))) "
            + buffers
            + ')) (unless (and physical-firefox physical-ghostty) (error "Waiting for apps")) (delete-other-windows) (switch-to-buffer physical-ghostty) (set-window-buffer (split-window-right) physical-firefox) (redisplay t) t)'
        )
        machine.wait_until_succeeds(
            user("emacsclient", "--socket-name", "reka", "--eval", expression)
        )
        machine.sleep(timedelta(milliseconds=500))
        chrome = json.loads(
            machine.succeed(user("${browserProbe}/bin/reka-browser-probe", "geometry"))
        )
        native = placement("physical-firefox")
        click("physical-ghostty")
        machine.send_key("x")
        machine.sleep(timedelta(milliseconds=200))
        assert machine.succeed("cat /tmp/reka-ghostty-input") == "x"
        factor = native[2] / chrome["innerWidth"]
        click_at(
            native[0] + factor * (chrome["x"] + chrome["width"] / 2),
            native[1] + factor * (chrome["y"] + chrome["height"] / 2),
        )
        machine.send_key("y")
        machine.sleep(timedelta(milliseconds=200))
        value = json.loads(
            machine.succeed(user("${browserProbe}/bin/reka-browser-probe", "value"))
        )
        old_input = machine.succeed("cat /tmp/reka-ghostty-input")
        assert value == "y" and old_input == "x", (value, old_input, native, chrome)
        print(
            "PASS: hardware click on real Firefox address bar redirects hardware typing from Ghostty at scale1.25"
        )
        river_pid = machine.succeed("pgrep -x river").strip()

        def app_pid(unit):
            return machine.succeed(
                user("systemctl", "--user", "show", unit, "--property=MainPID", "--value")
            ).strip()

        original_apps = {unit: app_pid(unit) for unit in ("focus-ghostty", "focus-firefox")}
        machine.succeed(user("systemctl", "--user", "stop", "focus-reka"))
        machine.succeed(user("systemctl", "--user", "start", "focus-oxbow"))
        machine.wait_until_succeeds("pgrep -x oxbow")
        machine.sleep(timedelta(milliseconds=500))
        machine.succeed(user("systemctl", "--user", "stop", "focus-oxbow"))
        machine.succeed(user("systemctl", "--user", "start", "focus-reka"))
        machine.wait_until_succeeds(
            user(
                "emacsclient",
                "--socket-name",
                "reka",
                "--eval",
                '(unless reka-ready (error "Waiting for new manager"))',
            )
        )
        machine.wait_until_succeeds(
            user("emacsclient", "--socket-name", "reka", "--eval", expression)
        )
        machine.sleep(timedelta(milliseconds=500))
        chrome = json.loads(
            machine.succeed(user("${browserProbe}/bin/reka-browser-probe", "geometry"))
        )
        native = placement("physical-firefox")
        click("physical-ghostty")
        machine.send_key("g")
        machine.sleep(timedelta(milliseconds=200))
        assert machine.succeed("cat /tmp/reka-ghostty-input") == "xg"
        factor = native[2] / chrome["innerWidth"]
        click_at(
            native[0] + factor * (chrome["x"] + chrome["width"] / 2),
            native[1] + factor * (chrome["y"] + chrome["height"] / 2),
        )
        machine.send_key("z")
        machine.sleep(timedelta(milliseconds=200))
        value = json.loads(
            machine.succeed(user("${browserProbe}/bin/reka-browser-probe", "value"))
        )
        assert value.endswith("z") and value.count("z") == 1, value
        assert machine.succeed("cat /tmp/reka-ghostty-input") == "xg"
        assert machine.succeed("pgrep -x river").strip() == river_pid
        assert {unit: app_pid(unit) for unit in original_apps} == original_apps
        print(
            "PASS: hardware Firefox/Ghostty click focus survives Oxbow/ReKa handoff with compositor and apps preserved"
        )
    except Exception:
        print(machine.succeed("cat /tmp/reka-manager.log"))
        print(
            evaluate(
                "(mapcar (lambda(f)(list (frame-parameter f (quote name)) (mapcar (lambda(w)(buffer-name(window-buffer w))) (window-list f)))) (frame-list))"
            )
        )
        raise
  '';
}
