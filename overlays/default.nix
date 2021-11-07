{ pkgs, nur, dwm-flake, neovim-flake, st-flake, dwl-flake, scripts, homeage, system, lib, myPkgs }:

let
  dwl-config = builtins.readFile ./dwl-config.c;
in
{
  overlays = [
    nur.overlay
    neovim-flake.overlay."${system}"
    dwl-flake.overlay."${system}"
    scripts.overlay
    (final: prev: {
      # Version of xss-lock that supports logind SetLockedHint
      xss-lock = prev.xss-lock.overrideAttrs (old: {
        src = prev.fetchFromGitHub {
          owner = "xdbob";
          repo = "xss-lock";
          rev = "7b0b4dc83ff3716fd3051e6abf9709ddc434e985";
          sha256 = "TG/H2dGncXfdTDZkAY0XAbZ80R1wOgufeOmVL9yJpSk=";
        };
      });
      xorg = prev.xorg // {
        # Override xorgserver with patch to set x11 type
        xorgserver = lib.overrideDerivation prev.xorg.xorgserver (drv: {
          patches = drv.patches ++ [ ./x11-session-type.patch ];
        });
      };
      #tlp = prev.tlp.overrideAttrs (old: {
      #  version = "1.4.1-beta.2";

      #  src = prev.fetchFromGitHub {
      #    owner = "linrunner";
      #    repo = "TLP";
      #    rev = "1.4.0-beta.2";
      #    sha256 = "coYgKeeTaR8LKUFWxPd5rhJ8x8PfHxTw+jnF87IA6K0=";
      #  };

      #  patches = [ ./makefile_service.patch ];
      #  postInstall = old.postInstall + ''
      #    mv $out/share/tlp/bat.d $out/usr/share/tlp/bat.d
      #  '';
      #});
      dwmJD = dwm-flake.packages.${system}.dwmJD;
      stJD = st-flake.packages.${system}.stJD;
      weechatJD = prev.weechat.override {
        configure = { availablePlugins, ... }: {
          scripts = with prev.weechatScripts; [
            weechat-matrix
          ];
        };
      };
      dwlJD = prev.dwl.override {
        conf = dwl-config;
      };
      nixUnstable = prev.nixUnstable.override {
        patches = [ ./unset-is-match.patch ];
      };
      inherit homeage;
      inherit myPkgs;
    })
  ];
}
