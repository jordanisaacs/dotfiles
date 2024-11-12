{ system, pkgs, lib, secrets, scripts, inputs }: {
  overlays = [
    scripts.overlay
    inputs.nur.overlay
    inputs.dwl-flake.overlays.default
    inputs.efi-power.overlays.default
    inputs.nixd.overlays.default

    (self: super: {
      waybar-master = inputs.nixpkgs-wayland.packages.${super.system}.waybar;

      awatcher = super.rustPlatform.buildRustPackage rec {
        pname = "awatcher";
        version = "main";
        src = inputs.awatcher-src;

        cargoLock = {
          lockFile = "${inputs.awatcher-src}/Cargo.lock";
          outputHashes = {
            "aw-client-rust-0.1.0" =
              "sha256-M4I4knIMXsyih5Hqo+3BXCAhLKfWQXZF+9kJt88BAZQ=";
          };
        };

        nativeBuildInputs = [ super.pkg-config ];

        buildInputs = [ super.openssl ];
      };

      # Back to using upstream river.
      river-master = super.river;

      # Version of xss-lock that supports logind SetLockedHint
      xss-lock = super.xss-lock.overrideAttrs (oa: {
        src = super.fetchFromGitHub {
          owner = "xdbob";
          repo = "xss-lock";
          rev = "7b0b4dc83ff3716fd3051e6abf9709ddc434e985";
          sha256 = "TG/H2dGncXfdTDZkAY0XAbZ80R1wOgufeOmVL9yJpSk=";
        };
      });

      rivercarro-master =
        let deps = super.callPackage ./rivercarro.zig.zon.nix { };
        in super.rivercarro.overrideAttrs (oa: {
          version = "master";
          src = inputs.rivercarro-src;
          inherit deps;
          nativeBuildInputs = with super; [
            pkg-config
            river-master
            wayland
            wayland-protocols
            wayland-scanner
            zig_0_13.hook
          ];
          zigBuildFlags = [ "--system" "${deps}" ];
        });

      # Commented out because need to update the patch
      # xorg = prev.xorg // {
      #   # Override xorgserver with patch to set x11 type
      #   xorgserver = lib.overrideDerivation prev.xorg.xorgserver (drv: {
      #     patches = drv.patches ++ [ ./x11-session-type.patch ];
      #   });
      # };

      inherit (import ../configs/editor.nix super
        inputs.neovim-flake.lib.neovimConfiguration)
        neovimJD;
      inherit (inputs.dwm-flake.packages.${system}) dwmJD;
      inherit (inputs.emacs-config.packages.${system}) emacs-jd;
      inherit (inputs.st-flake.packages.${system}) stJD;
      weechatJD = super.weechat.override {
        configure = { availablePlugins, ... }: {
          scripts = with super.weechatScripts; [ weechat-matrix ];
        };
      };
      agenix-cli = inputs.agenix.packages."${system}".default;
      inherit (inputs.deploy-rs.packages."${system}") deploy-rs;
      jdpkgs = inputs.jdpkgs.packages."${system}";
      bm-font = super.callPackage (secrets + "/bm") { };
      ccid-udev = super.runCommand "ccid-udev" { } ''
        mkdir -p $out/lib/udev/rules.d/
        cp ${super.ccid}/lib/udev/rules.d/92_pcscd_ccid.rules $out/lib/udev/rules.d/
        sed -i '/Kobil/d' $out/lib/udev/rules.d/92_pcscd_ccid.rules
      '';

      inherit (inputs) homeage impermanence;
    })
  ];
}
