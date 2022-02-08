{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.pijul;
in
{
  options.jd.pijul = {
    enable = mkOption {
      description = "Enable pijul";
      type = types.bool;
      default = false;
    };

    username = mkOption {
      description = "Username for pijul";
      type = types.str;
      default = "jordan";
    };

    fullName = mkOption {
      description = "Full name for pijul";
      type = types.str;
      default = "Jordan Isaacs";
    };

    email = mkOption {
      description = "Email for pijul";
      type = types.str;
      default = "mail@jdisaacs.com";
    };

    secretKey = mkOption {
      description = "Secret key for pijul";
      type = types.path;
      default = ./secretkey.json.age;
    };
  };

  config = mkIf (cfg.enable) {
    home.packages = with pkgs; [
      pijul
    ];

    #xdg.configFile = {
    #  "pijul/publickey.json".source = ./publickey.json;

    #  "pijul/config.toml".text = ''
    #    [author]
    #    name = "${cfg.username}"
    #    full_name = "${cfg.fullName}"
    #    email = "${cfg.email}"
    #  '';
    #} // (
    #  let
    #    public_key = builtins.fromJSON (readFile ./publickey.json);
    #  in
    #  {
    #    "pijul/identities/${public_key.key}".text = builtins.toJSON {
    #      inherit public_key;
    #      login = "nixos";
    #    };
    #  }
    #);

    #homeage.file = {
    #  "pijulsecret" = {
    #    source = cfg.secretKey;
    #    decryptPath = "pijul/secretkey.json";
    #    lnOnStartup = [
    #      "${config.xdg.configHome}/pijul/secretkey.json"
    #    ];
    #  };
    #};
  };
}
