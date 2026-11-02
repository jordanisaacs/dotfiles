{ pkgs }:
let
  probe = pkgs.runCommand "trayscale-netmon-probe" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python ${./trayscale_netmon_fixture.py} ${pkgs.trayscale.src} ${pkgs.trayscale.goModules} ${pkgs.trayscale.go}/bin/go "$out/bin/trayscale-netmon-probe"
  '';
in
pkgs.testers.runNixOSTest {
  name = "trayscale-netmon";
  nodes.machine = {
    virtualisation.vlans = [ ];
    networking.dhcpcd.enable = false;
    boot.kernelModules = [ "dummy" ];
    environment.systemPackages = [ pkgs.iproute2 ];
    systemd.services.trayscale-netmon-probe.serviceConfig = {
      ExecStart = "${probe}/bin/trayscale-netmon-probe";
      Type = "oneshot";
    };
  };
  testScript = ''
    import time

    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("systemctl start --no-block trayscale-netmon-probe")
    machine.wait_for_file("/run/trayscale-monitor-ready")
    # Documentation-only IPv6 on a synthetic link, entirely inside the VM.
    machine.succeed("ip link add synthetic0 type dummy")
    machine.succeed("ip link set synthetic0 up")
    machine.succeed("ip -6 address add 2001:db8::2/64 dev synthetic0 nodad")
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        state = machine.succeed("systemctl show trayscale-netmon-probe -p ActiveState --value").strip()
        if state in ("inactive", "failed"):
            break
        time.sleep(0.25)
    else:
        raise AssertionError("Trayscale monitor probe did not exit")
    probe_journal = machine.succeed("journalctl -u trayscale-netmon-probe --no-pager")
    result = machine.succeed("systemctl show trayscale-netmon-probe -p Result --value").strip()
    assert result == "success", probe_journal
    assert "monitor observed the new native IPv6 address" in probe_journal, probe_journal
  '';
}
