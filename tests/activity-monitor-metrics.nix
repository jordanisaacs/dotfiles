{ pkgs }:
let
  inherit (pkgs) lib;
  python = pkgs.python3.withPackages (p: [
    p.pynng
    p.protobuf
  ]);
  descriptors =
    pkgs.runCommand "magpie-protocol-descriptors" { nativeBuildInputs = [ pkgs.protobuf ]; }
      ''
        protoc --proto_path=${pkgs.mission-center.src}/subprojects/magpie/types/src \
          --include_imports --descriptor_set_out="$out" ipc.proto
      '';
in
pkgs.testers.runNixOSTest {
  name = "restricted-activity-monitor-metrics";

  nodes.machine =
    { config, ... }:
    let
      kernel = config.boot.kernelPackages.kernel;
      fixture = pkgs.stdenv.mkDerivation {
        pname = "activity-monitor-powercap-fixture";
        version = "1";
        src = ./powercap-fixture;
        nativeBuildInputs = kernel.moduleBuildDependencies;
        hardeningDisable = [ "pic" ];
        makeFlags = config.boot.kernelPackages.kernelModuleMakeFlags ++ [
          "-C"
          "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
          "M=$(PWD)"
          "INSTALL_MOD_PATH=$(out)"
          "INSTALL_MOD_DIR=extra"
        ];
        buildTargets = [ "modules" ];
        installTargets = [ "modules_install" ];
      };
    in
    {
      imports = [ ../modules/system/graphical/activity-monitor.nix ];
      virtualisation = {
        memorySize = 1536;
        cores = 2;
      };
      boot.extraModulePackages = [ fixture ];
      boot.kernelModules = [ "activity_monitor_powercap" ];
      jd.graphical.activityMonitor = {
        allowedUsers = [ "jd" ];
        networkMetrics = true;
        cpuEnergyMetrics = true;
      };
      users.users = {
        jd = {
          isNormalUser = true;
          uid = 1000;
          linger = true;
        };
        bob = {
          isNormalUser = true;
          uid = 1001;
          linger = true;
        };
      };
      environment.systemPackages = [
        pkgs.mission-center
        pkgs.libcap
        python
      ];
      environment.etc = {
        "metric-traffic.py".source = ./metric-traffic.py;
        "probe-metrics.py".source = ./probe_mission_center_metrics.py;
      };
      systemd.user.services = {
        metrics-probe = {
          environment = {
            PATH = lib.mkForce "/run/wrappers/bin:${
              lib.makeBinPath [
                pkgs.coreutils
                pkgs.procps
              ]
            }";
            RUST_LOG = "magpie=debug";
          };
          serviceConfig = {
            ExecStart = "${pkgs.mission-center}/bin/missioncenter-magpie --addr ipc://%t/mission-center-metrics.sock";
            KillMode = "control-group";
          };
        };
        metrics-traffic.serviceConfig.ExecStart = "${python.interpreter} /etc/metric-traffic.py client 192.168.1.2";
      };
    };

  nodes.peer = {
    virtualisation.memorySize = 512;
    networking.firewall.allowedTCPPorts = [ 8765 ];
    systemd.services.metrics-peer = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = "${pkgs.python3}/bin/python /etc/metric-traffic.py server";
    };
    environment.etc."metric-traffic.py".source = ./metric-traffic.py;
  };

  testScript = ''
    import shlex

    def user(name, *arguments):
        uid = {"jd": 1000, "bob": 1001}[name]
        return shlex.join([
            "runuser", "-u", name, "--", "env",
            f"XDG_RUNTIME_DIR=/run/user/{uid}",
            f"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus",
            "MAGPIE_DESCRIPTORS=${descriptors}",
            *arguments,
        ])

    start_all()
    machine.wait_for_unit("user@1000.service")
    machine.wait_for_unit("user@1001.service")
    peer.wait_for_unit("metrics-peer.service")
    peer.wait_for_open_port(8765)
    machine.succeed("udevadm settle")
    counter = "/sys/class/powercap/intel-rapl-fixture:0/energy_uj"
    assert machine.succeed("stat -Lc '%a %U %G' " + counter).strip() == "440 root activity-monitor"
    machine.succeed(user("jd", "cat", counter))
    machine.fail(user("jd", "test", "-w", counter))
    machine.fail(user("bob", "cat", counter))

    wrapper = "/run/wrappers/bin/nethogs"
    assert machine.succeed("stat -Lc '%a %U %G' " + wrapper).strip() == "550 root activity-monitor"
    caps = machine.succeed("getcap " + wrapper).strip()
    assert caps.endswith("cap_net_admin,cap_net_raw=ep"), caps
    machine.fail(user("bob", wrapper, "-V"))
    machine.succeed(user("jd", wrapper, "-V"))
    machine.succeed(user("jd", "systemctl", "--user", "start", "metrics-traffic.service", "metrics-probe.service"))
    traffic_pid = machine.succeed(user("jd", "systemctl", "--user", "show", "metrics-traffic.service", "-p", "MainPID", "--value")).strip()
    allowed = machine.succeed(user("jd", "${python.interpreter}", "/etc/probe-metrics.py", "allowed", "--traffic-pid", traffic_pid))
    print("Allowed metrics:", allowed)
    machine.succeed(user("bob", "systemctl", "--user", "start", "metrics-probe.service"))
    denied = machine.succeed(user("bob", "${python.interpreter}", "/etc/probe-metrics.py", "denied"))
    print("Denied metrics:", denied)

    # Inspect the production helper and its real child, not a substituted command.
    nethogs_pid = machine.succeed("pgrep -u jd -x nethogs").strip()
    status = dict(line.split(":", 1) for line in machine.succeed("cat /proc/" + nethogs_pid + "/status").splitlines() if ":" in line)
    assert set(status["Uid"].split()) == {"1000"}, status
    assert int(status["CapEff"].strip(), 16) == (1 << 12) | (1 << 13), status
    assert int(status["CapPrm"].strip(), 16) == (1 << 12) | (1 << 13), status
    magpie_pid = machine.succeed(user("jd", "systemctl", "--user", "show", "metrics-probe.service", "-p", "MainPID", "--value")).strip()
    magpie_status = machine.succeed("cat /proc/" + magpie_pid + "/status")
    assert "CapEff:\t0000000000000000" in magpie_status, magpie_status
    machine.fail("pgrep -u bob -x nethogs")
    machine.succeed(user("jd", "systemctl", "--user", "stop", "metrics-probe.service", "metrics-traffic.service"))
    machine.succeed(user("bob", "systemctl", "--user", "stop", "metrics-probe.service"))
    machine.fail("pgrep -x nethogs")
  '';
}
