{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.ssh;
in {
  options.jd.ssh = {
    enable = mkOption {
      description = "enable ssh";
      type = types.bool;
      default = false;
    };

    kerberos = {
      enable = mkOption {
        description = "enable kerberos";
        type = types.bool;
        default = false;
      };
    };
  };

  config =
    mkIf (cfg.enable)
    {
      home.packages = with pkgs;
        [
        ]
        ++ (
          if cfg.kerberos.enable
          then [krb5]
          else []
        );

      home.sessionVariables = mkIf (cfg.kerberos.enable) {
        KRB5_CONFIG = "${config.xdg.configHome}/krb5";
      };

      home.file."${config.xdg.configHome}/krb5/krb5.conf" = mkIf (cfg.kerberos.enable) {
        text = ''
          [libdefaults]
            default_realm = shark.ics.cs.cmu.edu
        '';
      };

      programs.ssh = {
        enable = true;
        matchBlocks = let
          base_setting = {
            forwardAgent = true;
          };

          afs_gpg_setting = {
            extraOptions = {
              "RemoteForward" = "/run/user/1000/gnupg/S.gpg-agent.extra /afs/andrew.cmu.edu/usr1/jisaacs/.gnupg/S.gpg-agent";
            };
          };

          setting =
            base_setting
            // (
              if config.jd.gpg.enable
              then afs_gpg_setting
              else {}
            );
        in {
          "unix.andrew.cmu.edu" = setting;
          "shark.ics.cs.cmu.edu" = setting;
        };
      };
    };
}
