{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.office365;
  onedriveLauncher = pkgs.writeShellScriptBin "onedrive-launcher" ''
    if [ -f ${config.xdg.configHome}/onedrive-launcher ]
    then
      for _onedrive_config_dirname_ in $(cat ${config.xdg.configHome}/onedrive-launcher | grep -v '[ \t]*#' )
      do
        systmctl --user start onedrive@$_onedrive_config_dirname_
      done
    else
      systemctl --user start onedrive@onedrive
    fi
  '';
in {
  options.jd.office365 = {
    enable = mkOption {
      description = "Enable office 365";
      type = types.bool;
      default = false;
    };

    onedriver = {
      enable = mkOption {
        description = "Enable onedriver client";
        type = types.bool;
        default = false;
      };

      mountpoint = mkOption {
        description = "Onedriver mount path";
        type = types.str;
        default = "${config.home.homeDirectory}/Onedrive";
      };
    };

    onedrive = {
      enable = mkOption {
        description = "Enable onedrive client";
        type = types.bool;
        default = false;
      };
    };
  };

  config = mkIf (cfg.enable) {
    # onedrive from https://github.com/NixOS/nixpkgs/blob/nixos-21.05/nixos/modules/services/networking/onedrive.nix
    home.packages =
      (
        if cfg.onedrive.enable
        then [pkgs.onedrive]
        else []
      )
      ++ (
        if cfg.onedriver.enable
        then [pkgs.jdpkgs.onedriverWrapper]
        else []
      );

    systemd.user.services = {
      "onedrive@" = mkIf (cfg.onedrive.enable) {
        Unit = {
          Description = "Onedrive sync service";
        };

        Service = {
          Type = "simple";
          ExecStart = "${pkgs.onedrive}/bin/onedrive --monitor \${XDG_CONFIG_HOME}/%i";
          Restart = "on-failure";
          RestartSec = 3;
          RestartPreventExitStatus = 3;
        };
      };

      onedriver-launcher = mkIf (cfg.onedriver.enable) {
        Unit = {
          Description = "onedrive file system mount service";
        };

        Service = {
          Type = "simple";
          ExecStart = "${pkgs.jdpkgs.onedriverWrapper}/bin/onedriverWrapper ${cfg.onedriver.mountpoint}";
        };

        Install = {
          WantedBy = ["default.target"];
        };
      };
    };

    home.activation = mkIf (cfg.onedriver.enable) {
      onedriverMountpoint = lib.hm.dag.entryAfter ["writeBoundary"] ''
        $DRY_RUN_CMD mkdir -p ${cfg.onedriver.mountpoint}
      '';
    };
  };
}
