{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.gpg;
in
{
  options.jd.gpg = {
    enable = mkOption {
      description = "enable gpg";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      pinentry-gnome
    ];

    programs.gpg = {
      enable = true;
      homedir = "${config.xdg.dataHome}/gnupg";
    };

    services.gpg-agent = {
      enable = true;
      pinentryFlavor = "gnome3";
      enableExtraSocket = true;
      enableScDaemon = false;
    };
  };
}
