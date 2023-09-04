{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.desktop;
in
{
  options.jd.desktop = {
    enable = mkOption {
      description = "Whether to enable desktop settings. Also tags as desktop for user settings";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    # security.tpm2 = {
    #   enable = true;
    #   # expose /run/current-system/sw/lib/libtpm2_pkcs11.so
    #   pkcs11.enable = true;
    #   # TPM2TOOLS_TCTI and TPM2_PKCS11_TCTI env variables
    #   tctiEnvironment.enable = true;
    # };
  };
}
