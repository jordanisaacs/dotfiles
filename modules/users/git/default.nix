{ pkgs
, config
, lib
, ...
}:
with lib; let
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
      description = "GPG signing key for git";
      type = types.bool;
      default = true;
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
      inherit (cfg) userName;
      inherit (cfg) userEmail;
      extraConfig = {
        commit.gpgSign = cfg.signByDefault;
        gpg = {
          format = "ssh";
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
        pull.rebase = "true";
        # https://blog.nilbus.com/take-the-pain-out-of-git-conflict-resolution-use-diff3/
        # https://stackoverflow.com/questions/27417656/should-diff3-be-default-conflictstyle-on-git
        merge.conflictstyle = "zdiff3";
      };
    };

    home.packages = with pkgs; [
      scripts.devTools
    ];
  };
}
