{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.git;
in {
  options.jd.git = {
    enable = mkOption {
      description = "Enable git";
      type = types.bool;
      default = false;
    };

    userName = mkOption {
      description = "Name for git";
      type = types.str;
      default = "Jordan Isaacs";
    };

    userEmail = mkOption {
      description = "Email for git";
      type = types.str;
      default = "github@jdisaacs.com";
    };
  };

  config = mkIf (cfg.enable) {
    programs.git = {
      enable = true;
      userName = cfg.userName;
      userEmail = cfg.userEmail;
      extraConfig = {
        credential.helper = "${
            pkgs.git.override { withLibsecret = true; }
          }/bin/git-credential-libsecret";
      };
    };

    home.packages = with pkgs; [
      scripts.devTools
    ];
  };
}
