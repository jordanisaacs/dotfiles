{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "trayscale-localapi";

  nodes.machine = {
    # No real credentials, profiles or network connections enter this VM.
    virtualisation.vlans = [ ];
    services.tailscale.enable = true;
    environment.etc = {
      "trayscale-api-probe.py".source = ./trayscale_api_probe.py;
      "trayscale-fixed-poller.go".source = "${pkgs.trayscale.src}/internal/tsutil/poller.go";
      "trayscale-stock-poller.go".source = "${pkgs.trayscale.src.src}/internal/tsutil/poller.go";
      "trayscale-sdk-backend.go".source = "${pkgs.trayscale.goModules}/tailscale.com/ipn/backend.go";
    };
    environment.systemPackages = [ pkgs.python3 ];
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("tailscaled.service")
    machine.wait_for_file("/run/tailscale/tailscaled.sock")
    machine.succeed("python /etc/trayscale-api-probe.py")
  '';
}
