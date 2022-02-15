{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.weechat;
in
{
  options.jd.weechat = {
    enable = mkOption {
      description = "Enable git";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (cfg.enable) {
    home.packages =
      let
        weechat = pkgs.weechat.override
          {
            configure = { availablePlugins, ... }: {
              scripts = with pkgs.weechatScripts; [
                weechat-autosort
              ];
            };
          };
      in
      [
        weechat
      ];
  };
}
