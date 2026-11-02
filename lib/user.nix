{
  pkgs,
  home-manager,
  inputs,
  ...
}:
with builtins;
{
  mkHMUser =
    {
      userConfig,
      username,
      machineData ? null,
    }:
    let

      machineModule =
        {
          lib,
          ...
        }:
        {
          options.machineData = lib.mkOption {
            default = { };
            type = lib.types.attrs;
            description = "Host settings passed explicitly from the flake.";
          };

          config.machineData =
            if machineData != null then
              machineData
            else
              throw "Choose a host-specific Home Manager target (for example jd@framework).";
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
    {
      name,
      groups,
      uid,
      shell,
      password ? null,
      ...
    }:
    {
      users.users."${name}" = {
        inherit name;
        isNormalUser = true;
        isSystemUser = false;
        extraGroups = groups;
        inherit uid;
        inherit shell;
      }
      // (
        if password == null then
          {
            initialPassword = "helloworld";
          }
        else
          {
            hashedPassword = password;
          }
      );
    };
}
