{
  pkgs,
  river ? pkgs.river-reka-with-health,
}:
let
  abiProbe = import ./river-health-abi.nix { inherit pkgs river; };
  fixture = import ./river-health-fixture.nix { inherit pkgs; };
in
pkgs.runCommand "river-native-client-health"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    STOCK_RIVER = "${pkgs.river}/bin/river";
    HEALTH_RIVER = "${river}/bin/river";
    HEALTH_CLIENT = "${pkgs.river-health}/bin/river-health";
    HEALTH_FIXTURE = "${fixture}/bin/river-health-fixture";
    OXBOW = "${pkgs.oxbow}/bin/oxbow";
    GTK_DEMO = "${pkgs.gtk3.dev}/bin/gtk3-demo";
    OXCTL = "${pkgs.oxbow}/bin/oxctl";
    XWAYLAND = "${pkgs.xwayland}/bin/Xwayland";
    XMESSAGE = "${pkgs.xmessage}/bin/xmessage";
    requiredSystemFeatures = [ ];
    meta.timeout = 120;
  }
  ''
    ${abiProbe}/bin/river-health-abi
    python -B ${./test_river_health.py}
    touch "$out"
  ''
