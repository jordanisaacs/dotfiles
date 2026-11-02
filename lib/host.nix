{
  system,
  pkgs,
  lib,
  inputs,
  utils,
}:
with builtins;
with utils;
{
  mkISO =
    {
      name,
      systemConfig ? { },
    }:
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

  mkHost =
    {
      name,
      systemConfig,
      cpuCores,
      stateVersion,
      passthru ? { },
      gpuTempSensor ? null,
      cpuTempSensor ? null,
    }:
    let
      enable = [ "enable" ];

      toplevelModules = [
        {
          attrPath = [ "isQemuGuest" ];
          keepAttr = false;
          module = import (inputs.nixpkgs + "/nixos/modules/profiles/qemu-guest.nix");
          config = {
            services.qemuGuest.enable = true;
          };
        }
        {
          attrPath = [ "impermanence" ];
          inherit enable;
        }
        {
          attrPath = [
            "debug"
            "dwarffs"
          ];
          inherit enable;
          module = inputs.dwarffs.nixosModules.dwarffs;
        }
      ];

      finalConfig = foldl' (accum: toplevel: enableModuleConfig toplevel accum) {
        config = systemConfig;
        extraModules = [
          inputs.agenix.nixosModules.age
          inputs.simple-nixos-mailserver.nixosModule
          inputs.impermanence.nixosModule
          passthru
        ];
      } toplevelModules;

      userCfg = config: {
        inherit
          name
          systemConfig
          cpuCores
          gpuTempSensor
          cpuTempSensor
          ;
        keybindings = config.jd.keybindings;
        greetdDefaultWindowManager = config.jd.greetd.defaultWindowManager;
      };
    in
    lib.nixosSystem {
      inherit system;

      modules = [
        (import ../modules/system { inherit inputs; })
        (
          { config, ... }:
          {
            jd = finalConfig.config;

            system.stateVersion = stateVersion;

            environment.etc = {
              "hmsystemdata.json".text = toJSON (userCfg config);
            };

            networking.hostName = name;

            nixpkgs.pkgs = pkgs;
            nix.settings.max-jobs = lib.mkDefault cpuCores;
          }
        )
      ]
      ++ finalConfig.extraModules;
    };
}
