{ pkgs, config, lib, ... }:
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
      default = "mail@jdisaacs.com";
    };

    signByDefault = mkOption {
      description = "GPG signing key for git";
      type = types.bool;
      default = true;
    };
  };

  config = mkIf (cfg.enable) {
    programs.git = {
      enable = true;
      userName = cfg.userName;
      userEmail = cfg.userEmail;
      extraConfig = {
        commit.gpgSign = cfg.signByDefault;
        gpg = {
          format = "ssh";
          ssh = {
            defaultKeyCommand = "${pkgs.openssh}/bin/ssh-add -L";
            program = "${pkgs.openssh}/bin/ssh-keygen";
            allowedSignersFile =
              let
                file = pkgs.writeTextFile {
                  name = "git-authorized-keys";
                  text = ''
                    mail@jdisaacs.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKIspidvrzy1NFoUXMEs1A2Wpx3E8nxzCKGZfBXyezV
                  '';
                };
              in
              builtins.toString file;
          };
        };
        credential.helper = "${
            pkgs.git.override { withLibsecret = true; }
          }/bin/git-credential-libsecret";
        init.defaultBranch = "main";
        pull.rebase = "true";
      };
    };

    home.packages = with pkgs; [
      scripts.devTools
    ];
  };
}
