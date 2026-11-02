{ pkgs }:
let
  probe = pkgs.writers.writePython3Bin "console-logging-probe" { } ''
    import os
    from pathlib import Path
    import sys

    phase = sys.argv[1]
    if phase == "flush-console":
        # The driver collects complete serial lines; password prompts normally
        # have no newline. Flush only output, without supplying input to it.
        Path("/dev/ttyS0").write_text("\n")
        raise SystemExit(0)
    counter = Path("/run/console-probe-" + phase)
    sequence = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(sequence))
    suffix = phase + "-" + str(sequence)
    descriptor = os.open("/dev/kmsg", os.O_WRONLY)
    try:
        os.write(descriptor, ("<3>QUIET-KERNEL-" + suffix + "\n").encode())
    finally:
        os.close(descriptor)
    print("QUIET-JOURNAL-" + suffix, flush=True)
  '';
  # The test harness normally forces loglevel=7 and forwards the complete
  # journal to serial. Evaluate the real policy outside those test overrides.
  consoleLevel =
    quiet:
    (import "${pkgs.path}/nixos/lib/eval-config.nix" {
      inherit pkgs;
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        ../modules/system/kernel
        { jd.kernel.quiet = quiet; }
      ];
    }).config.boot.consoleLogLevel;
  node =
    quiet:
    { lib, ... }:
    {
      imports = [
        ../modules/system/kernel
        ../modules/system/initrd
      ];
      jd = {
        kernel.quiet = quiet;
        initrd.quiet = quiet;
      };
      virtualisation.memorySize = 768;
      services.journald.settings.Journal.ForwardToConsole = lib.mkForce false;
      systemd.settings.Manager.ShowStatus = lib.mkForce true;
      boot = {
        consoleLogLevel = lib.mkForce (consoleLevel quiet);
        initrd.systemd = {
          contents."/etc/systemd/journald.conf".text = lib.mkForce ''
            [Journal]
            ForwardToConsole=no
          '';
          settings.Manager.ShowStatus = lib.mkForce true;
          services.console-status-capture = {
            description = "Record initrd console presentation mode";
            unitConfig.DefaultDependencies = false;
            wantedBy = [ "initrd.target" ];
            before = [ "initrd-switch-root.target" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "/bin/systemctl show --property=ShowStatus";
              StandardOutput = "append:/run/console-initrd-status";
            };
          };
        };
      };
      systemd.services = {
        # Test instrumentation makes tty0 /dev/console. Direct the unchanged
        # native agent to the serial device controlled by send_console instead.
        systemd-ask-password-console.serviceConfig.ExecStart = [
          ""
          "${pkgs.systemd}/bin/systemd-tty-ask-password-agent --watch --console=/dev/ttyS0"
        ];
        console-logging-probe = {
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StandardOutput = "journal";
            ExecStart = "${probe}/bin/console-logging-probe boot";
            ExecStop = "${probe}/bin/console-logging-probe shutdown";
          };
        };
        console-failure-probe = {
          description = "QUIET-STATUS-SENTINEL";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.coreutils}/bin/false";
          };
        };
        console-password-probe.serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.systemd}/bin/systemd-ask-password --no-tty --timeout=30 QUIET-PASSWORD-PROMPT";
          StandardOutput = "null";
        };
      };
    };
in
pkgs.testers.runNixOSTest {
  name = "quiet-console-journal-and-password";
  nodes = {
    loud = node false;
    quiet = node true;
  };
  testScript = ''
    from datetime import timedelta

    start_all()
    for machine in (loud, quiet):
        machine.wait_for_unit("multi-user.target")
        machine.wait_for_unit("console-logging-probe.service")
        machine.wait_until_succeeds("systemctl is-failed console-failure-probe.service")
        assert "QUIET-KERNEL-boot-1" in machine.succeed("journalctl -b -k --no-pager -g QUIET-KERNEL-boot-1")
        assert "QUIET-JOURNAL-boot-1" in machine.succeed("journalctl -b -u console-logging-probe --no-pager -g QUIET-JOURNAL-boot-1")
        assert "QUIET-STATUS-SENTINEL" in machine.succeed("journalctl -b -u console-failure-probe --no-pager")
        assert machine.succeed("systemctl show -p LogLevel").strip() == "LogLevel=info"

    loud.wait_for_console_text("QUIET-KERNEL-boot-1")
    assert loud.succeed("systemctl show -p ShowStatus").strip() == "ShowStatus=yes"
    assert quiet.succeed("cat /proc/sys/kernel/printk").split()[0] == "0"
    assert quiet.succeed("systemctl show -p ShowStatus").strip() == "ShowStatus=no"
    assert quiet.succeed("cat /run/console-initrd-status").strip() == "ShowStatus=no"
    assert "QUIET-KERNEL-boot-1" not in quiet.get_console_log()
    assert "QUIET-STATUS-SENTINEL" not in quiet.get_console_log()

    # Console presentation does not redirect or disable native password agents.
    quiet.succeed("systemctl start systemd-ask-password-console.path")
    quiet.succeed("systemctl start --no-block console-password-probe.service")
    quiet.wait_for_unit("systemd-ask-password-console.service")
    for attempt in range(30):
        quiet.succeed("${probe}/bin/console-logging-probe flush-console")
        quiet.sleep(duration=timedelta(milliseconds=100))
        if "QUIET-PASSWORD-PROMPT" in quiet.get_console_log():
            break
    else:
        raise AssertionError("Native password prompt did not reach the console")
    quiet.send_console("public-vm-fixture\n")
    quiet.wait_until_succeeds("systemctl show console-password-probe -p SubState | grep -Fx SubState=dead")
    assert quiet.succeed("systemctl show console-password-probe -p Result").strip() == "Result=success"
    assert quiet.succeed("systemctl show console-password-probe -p ExecMainStatus").strip() == "ExecMainStatus=0"

    for machine in (loud, quiet):
        machine.succeed("systemctl stop console-logging-probe.service")
        assert "QUIET-KERNEL-shutdown-1" in machine.succeed("journalctl -b -k --no-pager -g QUIET-KERNEL-shutdown-1")
        assert "QUIET-JOURNAL-shutdown-1" in machine.succeed("journalctl -b -u console-logging-probe --no-pager -g QUIET-JOURNAL-shutdown-1")
        machine.succeed("systemctl start console-logging-probe.service")
    loud.wait_for_console_text("QUIET-KERNEL-shutdown-1")
    assert "QUIET-KERNEL-shutdown-1" not in quiet.get_console_log()
    for machine in (loud, quiet):
        machine.shutdown()
    assert "QUIET-KERNEL-shutdown-2" in loud.get_console_log()
    assert "QUIET-KERNEL-shutdown-2" not in quiet.get_console_log()
  '';
}
