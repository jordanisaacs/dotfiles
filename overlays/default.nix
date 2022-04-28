{ pkgs, nur, dwm-flake, deploy-rs, neovim-flake, st-flake, dwl-flake, scripts, homeage, system, lib, jdpkgs, extra-container, impermanence, agenix }:

let
  dwl-config = builtins.readFile ./dwl-config.c;

in
{
  overlays = [
    nur.overlay
    neovim-flake.overlay
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
      # Commented out because need to update the patch
      # xorg = prev.xorg // {
      #   # Override xorgserver with patch to set x11 type
      #   xorgserver = lib.overrideDerivation prev.xorg.xorgserver (drv: {
      #     patches = drv.patches ++ [ ./x11-session-type.patch ];
      #   });
      # };
      dwmJD = dwm-flake.packages.${system}.dwmJD;
      stJD = st-flake.packages.${system}.stJD;
      weechatJD = prev.weechat.override {
        configure = { availablePlugins, ... }: {
          scripts = with prev.weechatScripts; [
            weechat-matrix
          ];
        };
      };

      agenix-cli = agenix.defaultPackage."${system}";
      deploy-rs = deploy-rs.packages."${system}".deploy-rs;
      jdpkgs = jdpkgs.packages."${system}";
      inherit homeage extra-container impermanence;
    })
  ];
}
