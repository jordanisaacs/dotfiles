{ config
, lib
, pkgs
, ...
}:
with lib; let
  cfg = config.jd.acme;
in
{
  options.jd.acme = {
    email = mkOption {
      description = "Email to register with acme";
      type = types.str;
    };
  };
}
