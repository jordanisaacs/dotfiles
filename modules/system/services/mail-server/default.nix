{ config
, lib
, pkgs
, ...
}:
with lib; let
  cfg = config.jd.mailserver;

  friendlyName = lib.strings.stringAsChars
    (x:
      if x == "@"
      then "_"
      else x);

  accountConf = _: {
    options = {
      hashedPasswordFile = mkOption {
        description = "The encrypted hashed password file";
        type = types.path;
      };

      aliases = mkOption {
        description = "A list of aliases of this login account. Note: Use list entries like “@example.com” to create a catchAll that allows sending from all email addresses in these domain.";
        type = with types; listOf str;
        default = [ ];
      };

      sendOnly = mkOption {
        description = "Specifies if the account should be a send-only account. Emails sent to send-only accounts will be rejected from unauthorized senders with the sendOnlyRejectMessage stating the reason.";
        type = types.bool;
        default = false;
      };
    };
  };
in
{
  options.jd.mailserver = {
    enable = mkOption {
      description = "Enable mailserver";
      type = types.bool;
      default = false;
    };

    fqdn = mkOption {
      description = "The fully qualified domain name of the mail server.";
      type = types.str;
    };

    sendingFqdn = mkOption {
      description = "The fully qualified domain name of the mail server.";
      default = cfg.fqdn;
      type = types.str;
    };

    domains = mkOption {
      description = "The domains that this mail server serves.";
      type = with types; listOf str;
    };

    mailDirectory = mkOption {
      description = "Where to store the mail";
      type = types.path;
      default = "/var/mailserver/mail";
    };

    indexDirectory = mkOption {
      description = "Base directory to store the search indices. Don't need to be backed up";
      type = types.path;
      default = "/var/mailserver/index";
    };

    decryptFolder = mkOption {
      description = "Path to decrypt hashed password files to";
      type = types.path;
      default = "/etc/mailserver";
    };

    loginAccounts = mkOption {
      description = "The login account of the domain. Every account is mapped to a unix user, e.g. user1@example.com.";
      type = with types; attrsOf (submodule accountConf);
    };
  };

  config = mkIf cfg.enable {
    age.secrets = with lib;
      mapAttrs'
        (name: value: (nameValuePair
          "mailserver_pwd_${friendlyName name}"
          {
            file = value.hashedPasswordFile;
            path = "${cfg.decryptFolder}/${friendlyName name}";
            mode = "600";
          }))
        cfg.loginAccounts;

    security.acme = {
      acceptTerms = true;
      defaults.email = config.jd.acme.email;
    };

    # https://serverfault.com/questions/1064046/how-do-i-prevent-the-spf-helo-none-warning-when-sending-from-postfix
    services.postfix.config = {
      smtp_helo_name = cfg.sendingFqdn;
    };

    mailserver = {
      enable = true;
      inherit (cfg) fqdn;
      inherit (cfg) domains;

      # You let the server create a certificate via Let’s Encrypt.
      # Note that this implies that a stripped down webserver has to be
      # started. This also implies that the FQDN must be set as an A
      # record to point to the IP of the server. In particular port
      # 80 on the server will be opened
      certificateScheme = 3;
      localDnsResolver = mkIf config.jd.unbound.enable false;

      fullTextSearch.enable = false;
      openFirewall = true;

      hierarchySeparator = "/";
      inherit (cfg) mailDirectory;
      indexDir = cfg.indexDirectory;

      loginAccounts =
        builtins.mapAttrs
          (name: value:
            with value; {
              hashedPasswordFile = "/etc/mailserver/${friendlyName name}";
              inherit sendOnly aliases;
            })
          cfg.loginAccounts;
    };
  };
}
