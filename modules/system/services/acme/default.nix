{
  lib,
  ...
}:
with lib;
{
  options.jd.acme = {
    email = mkOption {
      description = "Email to register with acme";
      type = types.str;
    };
  };
}
