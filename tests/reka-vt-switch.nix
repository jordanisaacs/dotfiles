{
  pkgs,
  river ? pkgs.river-reka,
}:
let
  init = pkgs.writeText "reka-vt-init.el" ''
    (require 'reka)
    (require 'reka-simulation)
    (require 'server)
    (setq server-name "reka-vt" inhibit-startup-screen t
          initial-scratch-message nil confirm-kill-processes nil)
    (server-start)
    (reka-enable)
  '';
  manager = pkgs.writers.writePython3Bin "reka-vt-manager" { } ''
    import os
    log = os.open("/tmp/reka-vt-manager.log", os.O_WRONLY | os.O_CREAT, 0o600)
    os.dup2(log, 1)
    os.dup2(log, 2)
    os.close(log)
    executable = (
        "${pkgs.reka-emacs}"
        "/bin/emacs"
    )
    init = "${init}"
    os.execv(executable, [executable, "-Q", "--load", init])
  '';
  login = pkgs.writers.writePython3Bin "reka-vt-login" { flakeIgnore = [ "E501" ]; } ''
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
        "${manager}"
        "/bin/reka-vt-manager"
    )
    os.execv(executable, [executable, "-no-xwayland", "-c", manager])
  '';
in
pkgs.testers.runNixOSTest {
  name = "reka-drm-virtual-terminal-resume";
  nodes.machine = {
    boot.kernelPackages = pkgs.linuxPackages_latest;
    virtualisation = {
      memorySize = 2048;
      cores = 2;
      qemu.options = [ "-vga none -device virtio-gpu-pci" ];
    };
    hardware.graphics.enable = true;
    fonts.packages = [ pkgs.dejavu_fonts ];
    users.users.alice = {
      isNormalUser = true;
      uid = 1000;
      extraGroups = [
        "video"
        "input"
      ];
    };
    services.greetd = {
      enable = true;
      settings = {
        initial_session = {
          command = "${login}/bin/reka-vt-login";
          user = "alice";
        };
        default_session = {
          command = "${pkgs.greetd}/bin/agreety";
          user = "greeter";
        };
      };
    };
    environment.systemPackages = [
      pkgs.wev
      pkgs.wtype
      pkgs.wlr-randr
      pkgs.reka-emacs
    ];
  };
  testScript = ''
    from datetime import timedelta
    import json
    import shlex

    machine.wait_for_unit("greetd.service")
    machine.wait_until_succeeds("pgrep -x river")
    machine.wait_for_file("/run/user/1000/wayland-1")
    def user(*arguments):
        return shlex.join([
            "runuser", "-u", "alice", "--", "env",
            "XDG_RUNTIME_DIR=/run/user/1000", "WAYLAND_DISPLAY=wayland-1",
            *arguments,
        ])
    def evaluate(expression):
        return machine.succeed(user(
            "emacsclient", "--socket-name", "reka-vt", "--eval", expression,
        )).strip()
    machine.wait_until_succeeds(user(
        "emacsclient", "--socket-name", "reka-vt", "--eval",
        '(unless reka-ready (error "Not ready"))',
    ))
    outputs = json.loads(machine.succeed(user("wlr-randr", "--json")))
    assert len(outputs) == 1 and not outputs[0]["name"].startswith("HEADLESS"), outputs
    river_pid = machine.succeed("pgrep -x river").strip()
    emacs_pid = evaluate("(emacs-pid)")
    machine.succeed(user(
        "systemd-run", "--user", "--unit=reka-vt-keyboard",
        "--setenv=WAYLAND_DISPLAY=wayland-1", "--setenv=XDG_RUNTIME_DIR=/run/user/1000",
        "wtype", "-k", "F35", "-s", "300000",
    ))
    machine.succeed(user(
        "systemd-run", "--user", "--unit=reka-vt-client",
        "--setenv=WAYLAND_DISPLAY=wayland-1", "--setenv=XDG_RUNTIME_DIR=/run/user/1000",
        "stdbuf", "-oL", "wev",
    ))
    machine.wait_until_succeeds(user(
        "emacsclient", "--socket-name", "reka-vt", "--eval",
        '(unless (reka--list-buffers) (error "Waiting for app"))',
    ))
    # Explicitly arrange the existing app, so this test isolates output lifecycle
    # from the separate first-app-focus regression.
    evaluate('(progn (switch-to-buffer (car (append (reka--list-buffers) nil))) '
             '(tab-bar-mode 1) (tab-bar-rename-tab "preserved-workspace") (redisplay t) t)')
    frame_name = evaluate("(frame-parameter nil 'name)")
    client_pid = machine.succeed(user("systemctl", "--user", "show", "reka-vt-client", "-p", "MainPID", "--value")).strip()
    # virtio-gpu can retain an enabled output while the seat is inactive,
    # unlike the laptop's i915 backend. Explicitly cycle the output as well,
    # exercising the same river_output_v1.removed event seen in its journal.
    machine.succeed(user("wlr-randr", "--output", outputs[0]["name"], "--off"))
    machine.sleep(timedelta(milliseconds=300))
    # Reproduce opening a second terminal while its output is absent, rather
    # than only checking an application arranged before the interruption.
    machine.succeed(user(
        "systemd-run", "--user", "--unit=reka-vt-paused-client",
        "--setenv=WAYLAND_DISPLAY=wayland-1", "--setenv=XDG_RUNTIME_DIR=/run/user/1000",
        "stdbuf", "-oL", "wev",
    ))
    machine.wait_until_succeeds(user(
        "emacsclient", "--socket-name", "reka-vt", "--eval",
        '(unless (= 2 (length (reka--list-buffers))) (error "Waiting for second app"))',
    ))
    mode = next(mode for mode in outputs[0]["modes"] if mode["current"])
    mode_specification = str(mode["width"]) + "x" + str(mode["height"]) + "@" + str(mode["refresh"]) + "Hz"
    try:
        machine.wait_until_succeeds(user("wlr-randr", "--output", outputs[0]["name"], "--on", "--mode", mode_specification), timeout=timedelta(seconds=10))
    except Exception:
        print(machine.succeed("cat /tmp/reka-vt-manager.log"))
        print(machine.succeed(user("wlr-randr", "--json")))
        raise
    machine.sleep(timedelta(milliseconds=300))
    assert evaluate("(frame-parameter nil 'name)") == frame_name
    assert evaluate('(alist-get (quote name) (tab-bar--current-tab))') == '"preserved-workspace"'
    # Native simulation validates actual compositor placement, unlike an Emacs
    # get-buffer-window check, which can still see a hidden stale frame.
    evaluate('(with-current-buffer (window-buffer (selected-window)) (reka-send-keys "0"))')
    try:
        machine.wait_until_succeeds(user(
            "journalctl", "--user", "-u", "reka-vt-client", "-u", "reka-vt-paused-client",
            "--no-pager", "-g", "utf8: '0'",
        ), timeout=timedelta(seconds=10))
    except Exception:
        print(machine.succeed("cat /tmp/reka-vt-manager.log"))
        print(evaluate('(with-current-buffer "*Messages*" (buffer-string))'))
        raise
    for count in range(20):
        machine.succeed("chvt 2")
        machine.sleep(timedelta(milliseconds=300))
        machine.succeed("chvt 1")
        machine.sleep(timedelta(milliseconds=300))
        assert machine.succeed("pgrep -x river").strip() == river_pid
        assert evaluate("(emacs-pid)") == emacs_pid
        assert evaluate("(frame-parameter nil 'name)") == frame_name
        assert evaluate('(alist-get (quote name) (tab-bar--current-tab))') == '"preserved-workspace"'
        assert evaluate('(let ((buffers (append (reka--list-buffers) nil))) '
                        '(and (cl-every (lambda (buf) (get-buffer-window buf t)) buffers) '
                        '(memq (window-buffer (selected-window)) buffers) t))') == "t"
        assert machine.succeed(user("systemctl", "--user", "show", "reka-vt-client", "-p", "MainPID", "--value")).strip() == client_pid
        key = chr(ord("a") + count)
        evaluate('(with-current-buffer (window-buffer (selected-window)) (reka-send-keys "' + key + '"))')
        machine.wait_until_succeeds(user(
            "journalctl", "--user", "-u", "reka-vt-client", "-u", "reka-vt-paused-client",
            "--no-pager", "-g", "utf8: '" + key + "'",
        ), timeout=timedelta(seconds=10))
    machine.fail("journalctl -b --no-pager | grep -F 'panic: reached unreachable code'")
  '';
}
