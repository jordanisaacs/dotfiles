{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.git;
in
{
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
      default = "jordan@snowytrees.dev";
    };

    signByDefault = mkOption {
      description = "Sign commits by default";
      type = types.bool;
      default = true;
    };

    signWith = mkOption {
      description = "Sign with [ssh gpg]";
      type = types.enum [
        "ssh"
        "gpg"
      ];
      default = "gpg";
    };

    allowedSignerFile = mkOption {
      description = "Allowed ssh file for signing";
      type = types.str;
      default = "";
    };
  };

  config = mkIf cfg.enable {
    programs.git = {
      enable = true;
      settings = {
        user = {
          name = cfg.userName;
          email = cfg.userEmail;
        };
        commit.gpgSign = cfg.signByDefault;
        gpg = {
          program = "${pkgs.gnupg}/bin/gpg";
          format = mkIf (cfg.signWith == "ssh") "ssh";
          ssh = {
            defaultKeyCommand = "${pkgs.openssh}/bin/ssh-add -L";
            program = "${pkgs.openssh}/bin/ssh-keygen";
            allowedSignersFile = cfg.allowedSignerFile;
          };
        };
        # Use SSH now, don't need credential helper/libsecret
        # credential.helper = "${
        #     pkgs.git.override { withLibsecret = true; }
        #   }/bin/git-credential-libsecret";
        init.defaultBranch = "main";
        pull.ff = "true";
        pull.rebase = "true";
        # https://blog.nilbus.com/take-the-pain-out-of-git-conflict-resolution-use-diff3/
        # https://stackoverflow.com/questions/27417656/should-diff3-be-default-conflictstyle-on-git
        merge.conflictstyle = "zdiff3";
      };
    };

    home.packages = with pkgs; [
      delta
      scripts.devTools
    ];
  };
}
