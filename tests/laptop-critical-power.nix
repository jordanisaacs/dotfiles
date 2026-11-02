{ pkgs, systemConfig }:
let
  inherit (pkgs) lib;
  upower = systemConfig.services.upower.package;
  python = pkgs.python3.withPackages (p: [
    p.dbus-python
    p.python-dbusmock
    p.pygobject3
    p.packaging
  ]);
in
assert systemConfig.jd.laptop.enable;
assert systemConfig.services.upower.criticalPowerAction == "Hibernate";
assert systemConfig.boot.resumeDevice != "";
assert lib.any (swap: swap.device == systemConfig.boot.resumeDevice) systemConfig.swapDevices;
assert !lib.elem "nohibernate" systemConfig.boot.kernelParams;
pkgs.runCommand "laptop-critical-power"
  {
    nativeBuildInputs = [
      python
      pkgs.dbus
      pkgs.umockdev
    ];
    GI_TYPELIB_PATH = lib.makeSearchPath "lib/girepository-1.0" [
      upower
      pkgs.umockdev.out
    ];
    UPOWER_TEST_SOURCE = "${upower.src}/src/linux";
    UPOWER_TEST_CONFIG =
      pkgs.writeText "laptop-UPower.conf"
        systemConfig.environment.etc."UPower/UPower.conf".text;
  }
  ''
    mkdir src tools
    ln -s ${upower}/libexec/upowerd src/upowerd
    ln -s ${upower}/bin/upower tools/upower
    umockdev-wrapper ${python}/bin/python ${./laptop-critical-power.py}
    touch "$out"
  ''
