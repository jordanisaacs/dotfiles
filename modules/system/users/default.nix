{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.users;

  mkUser =
    { name
    , groups
    , uid
    , password
    ,
    }: {
      inherit name;
      value =
        {
          inherit name uid;
          isNormalUser = true;
          isSystemUser = false;
          extraGroups = groups;
        }
        // (
          if password == null
          then {
            initialPassword = "helloworld";
          }
          else {
            hashedPassword = password;
          }
        );
    };

  user = _: {
    options = {
      name = mkOption {
        type = types.str;
      };
      uid = mkOption {
        type = types.int;
      };
      groups = mkOption {
        type = with types; listOf str;
        default = [ ];
      };
      password = mkOption {
        type = with types; nullOr str;
        default = null;
      };
    };
  };
in
{
  options.jd.users = {
    users = mkOption {
      type = with types; listOf (submodule user);
      default = [ ];
    };

    mutableUsers = mkOption {
      description = "Whether users are mutable";
      type = types.bool;
      default = true;
    };

    rootPassword = mkOption {
      description = "Hashed root password";
      default = null;
      type = with types; nullOr str;
    };
  };

  config = {
    users.users =
      { root.initialHashedPassword = cfg.rootPassword; }
      // builtins.listToAttrs (builtins.map mkUser cfg.users);
    users.mutableUsers = cfg.mutableUsers;
  };
}
