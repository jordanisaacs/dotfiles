{ system, pkgs, home-manager, lib, user, inputs, ... }:

with builtins ;

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
    , kernelPatches
    , systemConfig
    , cpuCores
    , users
    , stateVersion
    , wifi ? [ ]
    , passthru ? { }
    , gpuTempSensor ? null
    , cpuTempSensor ? null
    }:
    let
      # Removes attributes by path. Used to remove module options when disabled
      # Example:
      # removeAttrByPath [ "x" "y" ] { x = { y = { f = 4; }; z = 3; } -> { x = { z = 3; }; }
      removeAttrByPath = with lib; attrPath: set:
        let
          removeAttrRec = recPath: rem: set':
            if recPath == [ ] then
              let
                removed = removeAttrs set' [ rem ];

                result = updateManyAttrsByPath [
                  {
                    path = (init attrPath);
                    update = old: removed;
                  }
                ]
                  set;
              in
              if isAttrs set' then
                result
              else
                set
            else
              if (hasAttr rem set') then
                removeAttrRec (drop 1 recPath) (head recPath) (getAttr rem set')
              else set;
        in
        if (length attrPath) == 0 then set
        else
          removeAttrRec (drop 1 attrPath) (head attrPath) set;

      # Enable a module if attribute exists and is true
      enableModule = module: path:
        if (lib.attrByPath path false systemConfig) then
          [ module ]
        else
          [{ }];

      # Enable a module if attribute exists and is activated, along with importing the respective config
      enableModuleWithConfig = module: path: activate:
        if (lib.attrByPath (path ++ activate) false systemConfig) then
          [
            module
            (import (inputs.self + "/modules/system/" + (lib.concatStringsSep "/" path)))
          ]
        else
          [{ }];

      # Remove the module options from systemConfig if the module is not activated
      removeModuleOptions = path: activate: config:
        if (lib.attrByPath (path ++ activate) false config) then
          config
        else
          removeAttrByPath path config;

      networkCfg = listToAttrs (map
        (n: {
          name = "${n}";
          value = { useDHCP = true; };
        })
        NICs);

      enable = [ "enable" ];
      extraContainerPath = [ "extraContainer" ];
      impermanencePath = [ "impermanence" ];
      qemuPath = [ "isQemuGuest" ];

      systemConfigStripped =
        (removeModuleOptions impermanencePath enable
          (removeModuleOptions extraContainerPath enable
            (removeAttrByPath qemuPath systemConfig)));

      userCfg = {
        inherit name NICs systemConfig cpuCores gpuTempSensor cpuTempSensor;
      };

      sys_users = (map (u: user.mkSystemUser u) users);

    in
    lib.nixosSystem {
      inherit system;

      modules = [
        {
          imports = [ (import ../modules/system { inherit inputs; }) ] ++ sys_users;

          jd = systemConfigStripped;

          environment.etc = {
            "hmsystemdata.json".text = toJSON userCfg;
          };

          networking.hostName = "${name}";
          networking.interfaces = networkCfg;
          networking.wireless.interfaces = wifi;
          networking.useDHCP = lib.mkDefault false; # Disable any new interface added that is not in config

          boot.initrd.availableKernelModules = initrdMods;
          boot.kernelModules = kernelMods;
          boot.kernelParams = kernelParams;
          boot.kernelPackages = kernelPackage;
          boot.kernelPatches = kernelPatches;

          nixpkgs.pkgs = pkgs;
          nix.maxJobs = lib.mkDefault cpuCores;

          system.stateVersion = stateVersion;
        }
        passthru
      ] ++
      (enableModule (import (inputs.nixpkgs + "/nixos/modules/profiles/qemu-guest.nix")) qemuPath) ++
      (enableModuleWithConfig inputs.impermanence.nixosModule impermanencePath enable) ++
      (enableModuleWithConfig inputs.extra-container.nixosModule extraContainerPath enable);
    };
}
