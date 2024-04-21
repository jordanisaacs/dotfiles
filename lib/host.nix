{ system, pkgs, lib, user, inputs, patchedPkgs, utils, }:
with builtins;
with utils; {
  mkISO = { name, systemConfig ? { } }:
    lib.nixosSystem {
      inherit system;

      specialArgs = { };

      modules = [
        (import ../modules/iso)
        {
          jd = systemConfig;

          networking.hostName = "${name}";
          isoImage.isoName = "${name}";

          nixpkgs.pkgs = pkgs;
        }
      ];
    };

  mkHost = { name, systemConfig, cpuCores, stateVersion, passthru ? { }
    , gpuTempSensor ? null, cpuTempSensor ? null, }:
    let
      enable = [ "enable" ];
      moduleFolder = "modules/system/";

      toplevelModules = [
        {
          attrPath = [ "isQemuGuest" ];
          module =
            import (inputs.nixpkgs + "/nixos/modules/profiles/qemu-guest.nix");
          config = { services.qemuGuest.enable = true; };
        }
        {
          attrPath = [ "impermanence" ];
          inherit enable;
        }
        {
          attrPath = [ "debug" "dwarffs" ];
          inherit enable;
          module = inputs.dwarffs.nixosModules.dwarffs;
        }
      ];

      finalConfig =
        foldl' (accum: toplevel: enableModuleConfig toplevel accum) {
          config = systemConfig;
          extraModules = [
            inputs.agenix.nixosModules.age
            inputs.simple-nixos-mailserver.nixosModule
            inputs.impermanence.nixosModule
            passthru
          ];
        } toplevelModules;

      userCfg = {
        inherit name systemConfig cpuCores gpuTempSensor cpuTempSensor;
      };
    in lib.nixosSystem {
      inherit system;

      modules = [
        (import ../modules/system { inherit inputs patchedPkgs; })
        {
          jd = finalConfig.config;

          system.stateVersion = stateVersion;

          environment.etc = { "hmsystemdata.json".text = toJSON userCfg; };

          networking.hostName = name;

          nixpkgs.pkgs = pkgs;
          nix.settings.max-jobs = lib.mkDefault cpuCores;
        }
      ] ++ finalConfig.extraModules;
    };
}
