{
  pkgs,
  river ? pkgs.river,
}:
let
  layerClient = pkgs.stdenv.mkDerivation {
    name = "river-vt-layer-client";
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.pkg-config
      pkgs.wayland-scanner
    ];
    buildInputs = [ pkgs.wayland ];
    buildPhase = ''
      wayland-scanner client-header ${pkgs.wlr-protocols}/share/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml wlr-layer-shell-client.h
      wayland-scanner private-code ${pkgs.wlr-protocols}/share/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml wlr-layer-shell.c
      wayland-scanner private-code ${pkgs.wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml xdg-shell.c
      $CC -Wall -Wextra -I. ${./river_layer_churn.c} wlr-layer-shell.c xdg-shell.c $(pkg-config --cflags --libs wayland-client) -o river-vt-layer-client
    '';
    installPhase = ''
      install -Dm755 river-vt-layer-client "$out/bin/river-vt-layer-client"
    '';
  };
  login = pkgs.writers.writePython3Bin "river-vt-login" { flakeIgnore = [ "E501" ]; } ''
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
        "${pkgs.oxbow}"
        "/bin/oxbow"
    )
    os.execv(executable, [executable, "-no-xwayland", "-c", manager])
  '';
in
pkgs.testers.runNixOSTest {
  name = "river-drm-virtual-terminal-switch";
  nodes.machine = {
    boot.kernelPackages = pkgs.linuxPackages_latest;
    virtualisation = {
      memorySize = 1536;
      cores = 2;
      qemu.options = [ "-vga none -device virtio-gpu-pci" ];
    };
    hardware.graphics.enable = true;
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
          command = "${login}/bin/river-vt-login";
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
      layerClient
    ];
  };
  testScript = ''
    from datetime import timedelta
    import json
    machine.wait_for_unit("greetd.service")
    machine.wait_until_succeeds("pgrep -x river")
    machine.wait_for_file("/run/user/1000/wayland-1")
    prefix = "runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 "
    def user(command):
        return prefix + command
    machine.wait_until_succeeds(user("wlr-randr --json"))
    outputs = json.loads(machine.succeed(user("wlr-randr --json")))
    assert outputs and all(not o["name"].startswith("HEADLESS") for o in outputs), outputs
    river_pid = machine.succeed("pgrep -x river").strip()
    environment = "--setenv=WAYLAND_DISPLAY=wayland-1 --setenv=XDG_RUNTIME_DIR=/run/user/1000 "
    machine.succeed(user("systemd-run --user --unit=vt-observer " + environment + "stdbuf -oL wev"))
    machine.succeed(user("systemd-run --user --unit=vt-layer-churn " + environment + "river-vt-layer-client"))
    machine.wait_until_succeeds("pgrep -x wev", timeout=30)
    machine.succeed(user("systemctl --user is-active vt-layer-churn.service"))
    churn_pid = machine.succeed(user("systemctl --user show -p MainPID --value vt-layer-churn.service")).strip()
    client_pid = machine.succeed("pgrep -x wev").strip()
    for count in range(20):
        machine.succeed("chvt 2")
        machine.sleep(timedelta(milliseconds=150))
        machine.succeed("chvt 1")
        machine.sleep(timedelta(milliseconds=150))
        machine.succeed("kill -0 " + river_pid)
        machine.succeed("kill -0 " + client_pid)
        machine.succeed("kill -0 " + churn_pid)
    assert machine.succeed("pgrep -x river").strip() == river_pid
    assert machine.succeed("pgrep -x wev").strip() == client_pid
    machine.succeed(user("wlr-randr --json"))
    machine.succeed(user("wtype a"))
    machine.wait_until_succeeds(user("journalctl --user -u vt-observer.service --no-pager | grep -F \"utf8: 'a'\""), timeout=15)
    machine.fail("journalctl -b --no-pager | grep -F 'panic: reached unreachable code'")
  '';
}
