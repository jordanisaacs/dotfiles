{
  pkgs,
  river ? pkgs.river-reka-with-health,
}:
river.overrideAttrs (old: {
  outputs = [ "out" ];
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
  postPatch = (old.postPatch or "") + ''
    python ${./river_health_abi_build.py} ${./river-health-abi.zig} ${./river-health-abi.c}
  '';
  zigBuildFlags = (old.zigBuildFlags or [ ]) ++ [ "-Dhealth-abi-probe" ];
  postInstall = ''
    "$out/bin/river-health-abi"
  '';
  doInstallCheck = false;
})
