{ pkgs, config, lib, ... }:
with lib;
let cfg = config.jd.gpg;
in {
  options.jd.gpg = { enable = mkEnableOption "gpg"; };

  config = mkIf cfg.enable {
    programs.gpg = {
      enable = true;
      homedir = "${config.xdg.dataHome}/gnupg";
      settings = {
        personal-cipher-preferences = "AES256";
        personal-digest-preferences = "SHA512";
        personal-compress-preferences = "ZLIB BZIP2 ZIP Uncompressed";
        default-preference-list = "SHA512 AES256 ZLIB BZIP2 ZIP Uncompressed";
        cert-digest-algo = "SHA512";
        s2k-digest-algo = "SHA512";
        s2k-cipher-algo = "AES256";
        charset = "utf-8";
        fixed-list-mode = true;
        no-comments = true;
        no-emit-version = true;
        no-greeting = true;
        keyid-format = "0xlong";
        list-options = "show-uid-validity";
        verify-options = "show-uid-validity";
        with-key-origin = true;
        require-cross-certification = true;
        no-symkey-cache = true;
        use-agent = true;
        # throw-keyids = true;
      };
    };

    services.gpg-agent = {
      enable = true;
      pinentry.package = pkgs.pinentry-gnome3;
      enableExtraSocket = true;
      enableSshSupport = true;
      enableBashIntegration = true;
      enableScDaemon = true;
      sshKeys = [ "6B49022AD16FF1DEC5B9D2323855582D31C91076" ];
      defaultCacheTtl = 60;
      maxCacheTtl = 120;
    };
  };
}

