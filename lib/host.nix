{
  system,
  pkgs,
  lib,
  user,
  inputs,
  patchedPkgs,
  utils,
}:
with builtins;
with utils; {
  mkISO = {
    name,
    initrdMods,
    kernelMods,
    kernelParams,
    kernelPackage,
    systemConfig,
  }:
    lib.nixosSystem {
      inherit system;

      specialArgs = {};

      modules = [
        {
          imports = [../modules/iso];

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

  mkHost = {
    name,
    initrdMods,
    kernelMods,
    kernelParams,
    kernelPackage,
    kernelPatches,
    systemConfig,
    cpuCores,
    stateVersion,
    wifi ? [],
    passthru ? {},
    gpuTempSensor ? null,
    cpuTempSensor ? null,
  }: let
    enable = ["enable"];
    impermanencePath = ["impermanence"];
    qemuPath = ["isQemuGuest"];
    moduleFolder = "/modules/system/";

    systemConfigStripped =
      removeModuleOptions
      {
        path = impermanencePath;
        activate = enable;
      }
      (removeAttrByPath qemuPath systemConfig);

    systemEnableModule = enableModule systemConfig;
    systemEnableModuleConfig = enableModuleConfig systemConfigStripped;

    userCfg = {
      inherit name systemConfig cpuCores gpuTempSensor cpuTempSensor;
    };
  in
    lib.nixosSystem {
      inherit system;

      modules =
        [
          {
            imports = [(import ../modules/system {inherit inputs patchedPkgs;})];

            jd = systemConfigStripped;

            services.qemuGuest.enable = lib.mkIf (optionIsTrue systemConfig qemuPath) true;

            environment.etc = {
              "hmsystemdata.json".text = toJSON userCfg;
            };

            networking.hostName = name;

            boot.initrd.availableKernelModules = initrdMods;
            boot.kernelModules = kernelMods;
            boot.kernelParams = kernelParams;
            boot.kernelPackages = kernelPackage;
            boot.kernelPatches = kernelPatches;

            nixpkgs.pkgs = pkgs;
            nix.settings.max-jobs = lib.mkDefault cpuCores;

            system.stateVersion = stateVersion;
          }
          passthru
        ]
        ++ [inputs.agenix.nixosModules.age]
        ++ [inputs.simple-nixos-mailserver.nixosModule]
        ++ [inputs.impermanence.nixosModule]
        ++ (systemEnableModule (import (inputs.nixpkgs + "/nixos/modules/profiles/qemu-guest.nix")) qemuPath);
    };
}
