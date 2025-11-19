{
  system,
  pkgs,
  lib,
  secrets,
  scripts,
  inputs,
}:
{
  overlays = [
    scripts.overlay
    inputs.nur.overlays.default
    inputs.dwl-flake.overlays.default
    inputs.efi-power.overlays.default
    inputs.nixd.overlays.default

    (self: super: {
      # Version of xss-lock that supports logind SetLockedHint
      xss-lock = super.xss-lock.overrideAttrs (oa: {
        src = super.fetchFromGitHub {
          owner = "xdbob";
          repo = "xss-lock";
          rev = "7b0b4dc83ff3716fd3051e6abf9709ddc434e985";
          sha256 = "TG/H2dGncXfdTDZkAY0XAbZ80R1wOgufeOmVL9yJpSk=";
        };
      });

      rivercarro-master = super.rivercarro.overrideAttrs (oa: {
        version = "master";
        src = inputs.rivercarro-src;
        nativeBuildInputs = with super; [
          pkg-config
          river-classic
          wayland
          wayland-protocols
          wayland-scanner
          zig_0_15.hook
        ];
        postPatch = ''
          ln -s ${super.callPackage ./rivercarro.zig.zon.nix { }} $ZIG_GLOBAL_CACHE_DIR/p
        '';
      });

      # Commented out because need to update the patch
      # xorg = prev.xorg // {
      #   # Override xorgserver with patch to set x11 type
      #   xorgserver = lib.overrideDerivation prev.xorg.xorgserver (drv: {
      #     patches = drv.patches ++ [ ./x11-session-type.patch ];
      #   });
      # };

      inherit (import ../configs/editor.nix super inputs.neovim-flake.lib.neovimConfiguration)
        neovimJD
        ;
      inherit (inputs.dwm-flake.packages.${system}) dwmJD;
      inherit (inputs.emacs-config.packages.${system}) emacs-jd;
      inherit (inputs.st-flake.packages.${system}) stJD;
      weechatJD = super.weechat.override {
        configure =
          { availablePlugins, ... }:
          {
            scripts = with super.weechatScripts; [ weechat-matrix ];
          };
      };
      agenix-cli = inputs.agenix.packages."${system}".default;
      inherit (inputs.deploy-rs.packages."${system}") deploy-rs;
      jdpkgs = inputs.jdpkgs.packages."${system}";
      bm-font = super.callPackage (secrets + "/bm/berkeley-mono") { };
      bm-variable-font = super.callPackage (secrets + "/bm/berkeley-mono-variable") { };
      symbols-nerd-font =
        let
          pname = "nerd-icons-font";
          version = "unstable-2024-11-30"; # Using today's date for unstable version
        in
        super.stdenvNoCC.mkDerivation {
          name = "${pname}-${version}";

          src = super.fetchFromGitHub {
            owner = "rainstormstudio";
            repo = "nerd-icons.el";
            rev = "main";
            sha256 = "sha256-D3NXQE8yu+sDcpXTDndoqcaTnJlvLmVs3kvWfjflaJo=";
          };

          installPhase = ''
            runHook preInstall
            install -Dm644 fonts/*.ttf $out/share/fonts/truetype/NFM.ttf
            runHook postInstall
          '';
        };

      ccid-udev = super.runCommand "ccid-udev" { } ''
        mkdir -p $out/lib/udev/rules.d/
        cp ${super.ccid}/lib/udev/rules.d/92_pcscd_ccid.rules $out/lib/udev/rules.d/
        sed -i '/Kobil/d' $out/lib/udev/rules.d/92_pcscd_ccid.rules
      '';

      inherit (inputs) homeage impermanence;
    })
  ];
}
