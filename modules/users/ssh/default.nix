{ pkgs, config, lib, ... }:
with lib;

let
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

  config = mkIf (cfg.enable) {
    home.packages = with pkgs; [
    ] ++ (if cfg.kerberos.enable then [ krb5 ] else []);

    home.sessionVariables = mkIf (cfg.kerberos.enable) {
      KRB5_CONFIG = "${config.xdg.configHome}/krb5";
    };

    home.file."${config.xdg.configHome}/krb5/krb5.conf" = mkIf (cfg.kerberos.enable) {
      text = ''
        [libdefaults]
          default_realm = shark.ics.cs.cmu.edu
      '';
    };
  };
}
