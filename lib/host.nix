{ system, pkgs, home-manager, lib, user, ... }:
with builtins;
{
  mkISO = { name, initrdMods, kernelMods, kernelParams, kernelPackage, systemConfig }: lib.nixosSystem {
    inherit system;

    specialArgs = { };

    modules = [
      {
        imports = [ ../modules/iso ];

        networking.hostName = "${name}";
        networking.networkmanager.enable = true;
        networking.useDHCP = false;

        boot.initrd.availableKernelModules = initrdMods;
        boot.kernelModules = kernelMods;

        boot.kernelParams = kernelParams;
        boot.kernelPackages = kernelPackage;

        nixpkgs.pkgs = pkgs;
      }
    ];
  };

  mkHost =
    { name
    , NICs
    , initrdMods
    , kernelMods
    , kernelParams
    , kernelPackage
    , systemConfig
    , cpuCores
    , users
    , stateVersion ? "21.05"
    , wifi ? [ ]
    , passthru ? { }
    , gpuTempSensor ? null
    , cpuTempSensor ? null
    , enableSops ? false
    }:
    let
      networkCfg = listToAttrs (map
        (n: {
          name = "${n}";
          value = { useDHCP = true; };
        })
        NICs);

      userCfg = {
        inherit name NICs systemConfig cpuCores gpuTempSensor cpuTempSensor;
      };

      sys_users = (map (u: user.mkSystemUser u) users);

    in
    lib.nixosSystem {
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

          system.stateVersion = stateVersion;
        }
        (if enableSops then pkgs.sops-nix.nixosModules.sops else { })
        passthru
      ];
    };
}
