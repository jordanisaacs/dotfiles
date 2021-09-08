{ system, pkgs, home-manager, lib, user, ... }:
with builtins;
{
  mkHost = {
    name,
    NICs,
    initrdMods,
    kernelMods,
    kernelParams,
    kernelPackage,
    systemConfig,
    cpuCores,
    users,
    wifi ? [],
    gpuTempSensor ? null,
    cpuTempSensor ? null
  }:
  let
    networkCfg = listToAttrs (map (n: {
      name = "${n}"; value = { useDHCP = true; };
    }) NICs);

    userCfg = {
      inherit name NICs systemConfig cpuCores gpuTempSensor cpuTempSensor;
    };

    sys_users = (map (u: user.mkSystemUser u) users);

  in lib.nixosSystem {
    inherit system;

    modules = [
      {
        imports = [ ../modules/system ] ++ sys_users;

        jd = systemConfig;

        environment.etc = {
          "hmsystemdata.json".text = toJSON userCfg;
        };

        networking.hostName = "${name}";
        networking.interfaces = networkCfg;
        networking.wireless.interfaces = wifi;

        networking.networkmanager.enable = true;
        networking.useDHCP = false; # Disable any new interface added that is not in config

        boot.initrd.availableKernelModules = initrdMods;
        boot.kernelModules = kernelMods;
        boot.kernelParams = kernelParams;
        boot.kernelPackages = kernelPackage;

        nixpkgs.pkgs = pkgs;
        nix.maxJobs = lib.mkDefault cpuCores;

        system.stateVersion = "21.05";
      }
    ];
  };
}
