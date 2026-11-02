{
  pkgs,
  missionCenter,
  stock ? false,
}:
pkgs.runCommand "mission-center-${if stock then "stock" else "uwsm"}-apps"
  {
    nativeBuildInputs = with pkgs; [
      cargo
      rustc
      stdenv.cc
      patch
      python3
    ];
    MISSION_CENTER_SOURCE = missionCenter.src;
    MISSION_CENTER_VENDOR = missionCenter.cargoDeps;
    MISSION_CENTER_PATCH = ../overlays/mission-center-uwsm-apps.patch;
    MISSION_CENTER_INVENTORY = ./mission-center-app-inventory.rs;
  }
  ''
    python -B ${./test_mission_center_apps.py} "$out" ${pkgs.lib.optionalString stock "--stock"}
  ''
