{
  pkgs,
  river ? pkgs.river-reka-with-health,
}:
let
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
    OXCTL = "${pkgs.oxbow}/bin/oxctl";
    XWAYLAND = "${pkgs.xwayland}/bin/Xwayland";
    XMESSAGE = "${pkgs.xmessage}/bin/xmessage";
    requiredSystemFeatures = [ ];
    meta.timeout = 120;
  }
  ''
    python -B ${./test_river_health.py}
    touch "$out"
  ''
