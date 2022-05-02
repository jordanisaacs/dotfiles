{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.weechat;
in {
  options.jd.weechat = {
    enable = mkOption {
      description = "Enable git";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (cfg.enable) {
    home.packages = let
      myScripts = with pkgs;
        stdenv.mkDerivation {
          pname = "weechat-scripts";
          version = "0.1";

          src = builtins.fetchTarball {
            url = "https://github.com/weechat/scripts/tarball/5e0b5043f2bc1ca0a5e8f6c9cb30ff4e67a1062d";
            sha256 = "1kc5dpaprqlvmalwibb23l7xmhm6jxjccp88r1zfxd5impzq31hz";
          };

          passthru.scripts = ["autojoin.py"];

          dontBuild = true;
          doCheck = false;

          installPhase = ''
            install -D python/autojoin.py $out/share/autojoin.py
          '';
        };

      weechat =
        pkgs.weechat.override
        {
          configure = {availablePlugins, ...}: {
            scripts = with pkgs.weechatScripts; [
              weechat-autosort
              multiline
              myScripts
            ];
          };
        };
    in [
      weechat
    ];
  };
}
