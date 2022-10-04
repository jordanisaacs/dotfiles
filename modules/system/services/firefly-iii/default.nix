{
  config,
  lib,
  pkgs,
  ...
}:
# TODO: Incomplete
with lib; let
  cfg = config.jd.firefly-iii;
  name = "firefly-iii";
  dbName = "firefly_iii";
  user = name;
  group = user;

  firefly-iii = pkgs.jdpkgs.firefly-iii.override {
    dataDir = cfg.dataDir;
  };

  firefly-dir = "${firefly-iii}/share/php/firefly-iii";

  # Shell script for local administration
  artisan = pkgs.writeScriptBin "firefly-iii" ''
    #! ${pkgs.runtimeShell}
    cd ${firefly-dir}
    sudo=exec
    if [[ "$USER" != ${user} ]]; then
      sudo='exec /run/wrappers/bin/sudo -u ${user}'
    fi
    $sudo ${pkgs.php}/bin/php artisan $*
  '';
in {
  options.jd.firefly-iii = {
    enable = mkEnableOption "Firefly III";

    dataDir = mkOption {
      type = types.path;
      description = "Firefly III data directory";
      default = "/var/lib/${name}";
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
  };

  config = mkIf (cfg.enable) {
    users = {
      groups.${group} = {};
      users.${user} = {
        inherit group;
        description = "Firefly III user";
      };
    };

    services = {
      postgresql = {
        enable = true;
        ensureUsers = [
          {
            name = user;
            ensurePermissions = {
              "DATABASE ${dbName}" = "ALL PRIVILIGES";
            };
          }
        ];
        ensureDatabases = [dbName];
      };

      phpfpm.pools.${name} = {
        inherit user group;
        phpOptions = "
          log_errors = on
        ";
        settings = {
          "listen.owner" = user;
          "listen.group" = group;
          "pm" = "dynamic";
          "pm.max_children" = 5;
          "pm.start_servers" = 1;
          "pm.min_spare_servers" = 1;
          "pm.max_spare_servers" = 3;
          "pm.max_requests" = 500;
        };
      };

      nginx = {
        enable = true;
        virtualHosts."proxy" = {
          locations = {
            "/firefly-iii/" = {
              root = "${firefly-dir}/public";
              index = "index.php";
              tryFiles = "$uri $uri/ /index.php?$query_string";
            };
            "~ /firefly-iii/\.php$" = {
              root = "${firefly-dir}/public";
              extraConfig = ''
                fastcgi_pass unix:${config.services.phpfpm.pools.${name}.socket};
              '';
            };
            "~ /firefly-iii/\.(js|css|gif|png|ico|jpg|jpeg)$" = {
              root = "${firefly-dir}/public";
              extraConfig = ''
                expires 365d;
              '';
            };
          };
        };
      };
    };

    systemd.services."${name}-setup" = {
      description = "Preparation tasks for Firefly III";
      before = ["phpfpm-${name}.service"];
      requires = ["postgresql.service"];
      after = ["postgresql.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = user;
        WorkingDirectory = firefly-dir;
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
        # migrate db
        ${pkgs.php}/bin/php artisan migrate --force
      '';
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir}                            0710 ${user} ${group} --"
      "d ${cfg.dataDir}/storage                    0700 ${user} ${group} --"
      "d ${cfg.dataDir}/storage/app                0700 ${user} ${group} --"
      "d ${cfg.dataDir}/storage/database           0700 ${user} ${group} --"
      "d ${cfg.dataDir}/storage/export             0700 ${user} ${group} --"
      "d ${cfg.dataDir}/storage/framework          0700 ${user} ${group} --"
      "d ${cfg.dataDir}/storage/framework/cache    0700 ${user} ${group} --"
      "d ${cfg.dataDir}/storage/framework/sessions 0700 ${user} ${group} --"
      "d ${cfg.dataDir}/storage/framework/views    0700 ${user} ${group} --"
      "d ${cfg.dataDir}/storage/logs               0700 ${user} ${group} --"
      "d ${cfg.dataDir}/storage/upload             0700 ${user} ${group} --"
    ];
  };
}
