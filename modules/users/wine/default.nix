{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.wine;
in {
  options.jd.wine = {
    enable = mkOption {
      description = "enable wine";
      type = types.bool;
      default = false;

    };

    office365 = mkOption {
      description = "enable office365";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.enable (
    let
      dotDir = builtins.substring ((builtins.stringLength config.home.homeDirectory) + 1) (builtins.stringLength config.xdg.configHome) config.xdg.configHome;
      wineWrapper = import ./wrapper.nix { inherit pkgs; };
      config_dir = config.xdg.configHome;
    in
      mkMerge [
        (mkIf cfg.office365 (
          let
            executable = "${config.xdg.configHome}/wine/installers/office365install.exe";
            name = "office365";
            tricks = [ "msxml6" "riched20" ];
            firstRunScript = ''
            '';

            is64bits = false;
            office365 = wineWrapper {
              inherit executable name config_dir is64bits firstRunScript;
            };
          in {
            home.packages = [ office365 ];

            home.file."${dotDir}/wine/installers/office365install.exe" = {
              source = ./OfficeSetup.exe;
            };
          }))
     ]
  );
}
