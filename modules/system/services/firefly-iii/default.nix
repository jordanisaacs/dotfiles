{
  config,
  lib,
  pkgs,
  ...
}:
# TODO: Incomplete
with lib; let
  cfg = config.jd.firefly-iii;
  user = "firefly-iii";
  group = "phpfpm";

  fireflyPkg = pkgs.jdpkgs.firefly-iii.override {
    dataDir = cfg.dataDir;
  };

  dbConfig =
    {
      DB_CONNECTION = cfg.dbType;
    }
    // (optionalAttrs (cfg.dbType != "sqlite") {
      # DB_HOST = cfg.host;
      # DB_PORT = cfg.port;
      # DB_DATABASE = cfg.database;
      # DB_USERNAME = cfg.username;
      # DB_PASSWORD._secret = db.passwordFile;
    });

  appConfig = {
    # APP_URL = cfg.appURL;
    APP_KEY._secret = cfg.appKeyFile;
    # Leave the following configuration vars as is.
    # Unless you like to tinker and know what you're doing.
    APP_NAME = "FireflyIII";
    BROADCAST_DRIVER = "log";
    QUEUE_DRIVER = "sync";
    CACHE_PREFIX = "firefly";
    PUSHER_KEY = "";
    IPINFO_TOKEN = "";
    PUSHER_SECRET = "";
    PUSHER_ID = "";
    DEMO_USERNAME = "";
    DEMO_PASSWORD = "";
    IS_HEROKU = false;
    FIREFLY_III_LAYOUT = "v1";
    APP_URL = "http://localhost";
  };

  mailConfig = {
  };

  # Shell script for local administration
  artisan = pkgs.writeScriptBin "firefly-iii" ''
    #! ${pkgs.runtimeShell}
    cd ${fireflyPkg}
    sudo=exec
    if [[ "$USER" != ${user} ]]; then
      sudo='exec /run/wrappers/bin/sudo -u ${user}'
    fi
    $sudo ${pkgs.php82}/bin/php artisan $*
  '';
in {
  options.jd.firefly-iii = {
    enable = mkEnableOption "Firefly III";

    dataDir = mkOption {
      type = types.path;
      description = "Firefly III data directory";
      default = "/var/lib/firefly-iii";
    };

    appUrl = mkOption {
      type = types.str;
      description = "The root URL that you want to host Firefly III on. All URLS in Firefly III will be generated using this value.";
      default = "http://chairlift.wg/miniflux";
    };

    appKeyFile = mkOption {
      type = types.path;
      description = ''
        A file containing the Laravel APP_KEY - a 32 character long,
        base64 encoded key used for encryption where needed. Can be
        generated with head -c 32 /dev/urandom | base64
      '';
    };

    dbType = mkOption {
      type = types.enum ["pgsql" "mysql" "sqlite"];
      default = "sqlite";
      description = "Database engine to use.";
    };

    config = mkOption {
      type = with types;
        attrsOf
        (nullOr
          (either
            (oneOf [
              bool
              int
              port
              path
              str
            ])
            (submodule {
              options = {
                _secret = mkOption {
                  type = nullOr (oneOf [str path]);
                  description = ''
                    The path to a file containing the value the
                    option should be set to in the final
                    configuration file.
                  '';
                };
              };
            })));
      default = {};
      example = literalExpression ''
        {
          MAILGUN_SECRET = { _secret = "/run/keys/mailgun_secret" };
        }
      '';
      description = ''
        Firefly III configuration options to set in the <filename>.env</filename> file.

        Settings containing secret data should be set to an attribute
        set containing the attribute <literal>_secret</literal> - a
        string pointing to a file containing the value the option
        should be set to. See the example to get a better picture of
        this: in the resulting <filename>.env</filename> file, the
        <literal>MAILGUN_SECRET</literal> key will be set to the
        contents of the <filename>/run/keys/mailgun_secret</filename>
        file.
      '';
    };
  };

  config = mkIf (cfg.enable) {
    users = {
      users = {
        ${user} = {
          inherit group;
          isSystemUser = true;
        };
        "nginx" = {
          extraGroups = [group];
        };
      };
      groups = {
        ${group} = {};
      };
    };

    # PHP
    services.phpfpm.pools.firefly-iii = {
      inherit user;
      inherit group;
      phpPackage = pkgs.php82;
      phpOptions = ''
        log_errors = on
      '';
      settings = {
        "listen.mode" = "0660";
        "listen.owner" = user;
        "listen.group" = group;
        "pm" = "dynamic";
        "pm.max_children" = 32;
        "pm.start_servers" = 2;
        "pm.min_spare_servers" = 2;
        "pm.max_spare_servers" = 4;
        "pm.max_requests" = 500;
      };
      # // cfg.poolConfig;
    };

    # Reverse proxy
    services.nginx = {
      enable = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      virtualHosts."localhost" = {
        root = mkForce "${fireflyPkg}/public";
        locations = {
          "/" = {
            index = "index.php";
            tryFiles = "$uri $uri/ /index.php?$query_string";
          };
          "~ \.php$".extraConfig = ''
            fastcgi_pass unix:${config.services.phpfpm.pools."firefly-iii".socket};
          '';
          "~ \.(js|css|gif|png|ico|jpg|jpeg)$" = {
            extraConfig = "expires 365d;";
          };
        };
        # locations = {
        #   "^~ /budget/".extraConfig = ''
        #     root ${fireflyPkg}/public;
        #     index index.php;
        #     try_files @budget /index.php?$query_string;

        #     location ~* \.php(?:$|/) {
        #       # include ${pkgs.nginx}/conf/fastcgi_params;
        #       # include ${pkgs.nginx}/conf/fastcgi.conf;
        #       # fastcgi_param SCRIPT_FILENAME $request_filename;
        #       # fastcgi_param modHeadersAvailable true; # avoid sending security headers twice
        #       fastcgi_pass unix:${config.services.phpfpm.pools."firefly-iii".socket};
        #     }

        #     location ~* \.(js|css|gif|png|ico|jpg|jpeg)$ {
        #       expires 365d;
        #     }
        #   '';
        #   "@budget".extraConfig = ''
        #     rewrite ^/budget/(.*)$ /index.php/$1 last;
        #   '';
        # };
      };
    };

    # Config
    jd.firefly-iii.config = appConfig // dbConfig // mailConfig;

    # Set-up script
    environment.systemPackages = [artisan];

    systemd.tmpfiles.rules =
      [
        "d ${cfg.dataDir}                            0710 ${user} ${group} - -"
        "d ${cfg.dataDir}/storage                    0700 ${user} ${group} - -"
        "d ${cfg.dataDir}/storage/app                0700 ${user} ${group} - -"
        "d ${cfg.dataDir}/storage/database           0700 ${user} ${group} - -"
        "d ${cfg.dataDir}/storage/export             0700 ${user} ${group} - -"
        "d ${cfg.dataDir}/storage/framework          0700 ${user} ${group} - -"
        "d ${cfg.dataDir}/storage/framework/cache    0700 ${user} ${group} - -"
        "d ${cfg.dataDir}/storage/framework/sessions 0700 ${user} ${group} - -"
        "d ${cfg.dataDir}/storage/framework/views    0700 ${user} ${group} - -"
        "d ${cfg.dataDir}/storage/logs               0700 ${user} ${group} - -"
        "d ${cfg.dataDir}/storage/upload             0700 ${user} ${group} - -"
      ]
      ++ optional (cfg.dbType == "sqlite") "f ${cfg.dataDir}/database.sqlite  0700 ${user} ${group} - -";

    systemd.services."firefly-iii-setup" = {
      description = "Preparation tasks for Firefly III";
      before = ["phpfpm-firefly-iii.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = user;
        WorkingDirectory = fireflyPkg;
      };
      path = [pkgs.replace-secret];
      script = let
        isSecret = v: isAttrs v && v ? _secret && (isString v._secret || builtins.isPath v._secret);
        fireflyEnvVars = generators.toKeyValue {
          mkKeyValue = flip generators.mkKeyValueDefault "=" {
            mkValueString = v:
              with builtins;
                if isInt v
                then toString v
                else if isString v
                then v
                else if true == v
                then "true"
                else if false == v
                then "false"
                else if isSecret v
                then hashString "sha256" v._secret
                else throw "unsupported type ${typeOf v}: ${(generators.toPretty {}) v}";
          };
        };
        secretPaths = mapAttrsToList (_: v: v._secret) (filterAttrs (_: isSecret) cfg.config);
        mkSecretReplacement = file: ''
          replace-secret ${escapeShellArgs [(builtins.hashString "sha256" file) file "${cfg.dataDir}/.env"]}
        '';
        secretReplacements = concatMapStrings mkSecretReplacement secretPaths;
        filteredConfig = converge (filterAttrsRecursive (_: v: ! elem v [{} null])) cfg.config;
        fireflyEnv = pkgs.writeText "firefly-iii.env" (fireflyEnvVars filteredConfig);
      in ''
        set -euo pipefail
        umask 077

        # create the .env file
        install -T -m 0600 -o ${user} ${fireflyEnv} "${cfg.dataDir}/.env"
        ${secretReplacements}
        if ! grep 'APP_KEY=base64:' "${cfg.dataDir}/.env" >/dev/null; then
            sed -i 's/APP_KEY=/APP_KEY=base64:/' "${cfg.dataDir}/.env"
        fi
        echo "migration"
        # migrate db
        ${pkgs.php82}/bin/php artisan migrate --force
      '';
    };
  };
}
