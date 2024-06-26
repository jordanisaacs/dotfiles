{ pkgs
, home-manager
, lib
, system
, overlays
, inputs
, ...
}:
with builtins; {
  mkHMUser =
    { userConfig
    , username
    ,
    }:
    let
      trySettings = tryEval (fromJSON (readFile /etc/hmsystemdata.json));
      machineData =
        if trySettings.success
        then trySettings.value
        else { };

      machineModule =
        { pkgs
        , config
        , lib
        , ...
        }: {
          options.machineData = lib.mkOption {
            default = { };
            description = "Settings passed from nixos system configuration. If not present will be empty";
          };

          config.machineData = machineData;
        };
    in
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        ../modules/users
        machineModule
        inputs.impermanence.nixosModules.home-manager.impermanence
        pkgs.homeage.homeManagerModules.homeage
        {
          jd = userConfig;
          nixpkgs = {
            inherit overlays;
            config = {
              permittedInsecurePackages = [
                "electron-9.4.4"
              ];
              allowUnfree = true;
            };
          };

          home = {
            inherit username;
            stateVersion = "21.05";
            homeDirectory = "/home/${username}";
          };
          systemd.user.startServices = true;
        }
      ];
    };

  mkSystemUser =
    { name
    , groups
    , uid
    , shell
    , password ? null
    , ...
    }: {
      users.users."${name}" =
        {
          inherit name;
          isNormalUser = true;
          isSystemUser = false;
          extraGroups = groups;
          inherit uid;
          inherit shell;
        }
        // (
          if password == null
          then {
            initialPassword = "helloworld";
          }
          else {
            hashedPassword = password;
          }
        );
    };
}
