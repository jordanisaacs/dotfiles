{ pkgs
, secrets
, nixpkgs-stable
, nur
, dwm-flake
, deploy-rs
, neovim-flake
, st-flake
, dwl-flake
, scripts
, homeage
, system
, lib
, jdpkgs
, impermanence
, nixpkgs-wayland
, agenix
, efi-power
}: {
  overlays = [
    nur.overlay
    dwl-flake.overlays.default
    efi-power.overlays.default
    scripts.overlay

    (self: super: {
      inherit (nixpkgs-wayland.packages.${super.system}) waybar;

      # Version of xss-lock that supports logind SetLockedHint
      xss-lock = super.xss-lock.overrideAttrs (old: {
        src = super.fetchFromGitHub {
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

      inherit (import ../configs/editor.nix super neovim-flake.lib.neovimConfiguration) neovimJD;
      inherit (dwm-flake.packages.${system}) dwmJD;
      inherit (st-flake.packages.${system}) stJD;
      weechatJD = super.weechat.override {
        configure = { availablePlugins, ... }: {
          scripts = with super.weechatScripts; [
            weechat-matrix
          ];
        };
      };
      agenix-cli = agenix.packages."${system}".default;
      inherit (deploy-rs.packages."${system}") deploy-rs;
      jdpkgs = jdpkgs.packages."${system}";
      bm-font = super.callPackage (secrets + "/bm") { };
      inherit homeage impermanence;
    })
  ];
}
