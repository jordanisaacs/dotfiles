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
, inputs
, emacs-config
, river-src
, rivercarro-src
}: {
  overlays = [
    nur.overlay
    dwl-flake.overlays.default
    efi-power.overlays.default
    scripts.overlay

    (self: super: {
      waybar-master = nixpkgs-wayland.packages.${super.system}.waybar;

      awatcher = super.rustPlatform.buildRustPackage rec {
        pname = "awatcher";
        version = "main";
        src = inputs.awatcher-src;

        cargoLock = {
           lockFile = "${inputs.awatcher-src}/Cargo.lock";
           outputHashes = {
             "aw-client-rust-0.1.0" = "sha256-fCjVfmjrwMSa8MFgnC8n5jPzdaqSmNNdMRaYHNbs8Bo=";
           };
        };

        nativeBuildInputs = [
          super.pkg-config
        ];

        buildInputs = [
          super.openssl
        ];
      };

      river-master = super.river.overrideAttrs
        (oa: {
          version = "master";

          src = river-src;

          buildInputs = with super; [
            scdoc
            udev
            libevdev
            libinput
            pixman
            wlroots
            wayland-protocols
            libxkbcommon
          ];
        });

      # Version of xss-lock that supports logind SetLockedHint
      xss-lock = super.xss-lock.overrideAttrs (oa: {
        src = super.fetchFromGitHub {
          owner = "xdbob";
          repo = "xss-lock";
          rev = "7b0b4dc83ff3716fd3051e6abf9709ddc434e985";
          sha256 = "TG/H2dGncXfdTDZkAY0XAbZ80R1wOgufeOmVL9yJpSk=";
        };
      });

      rivercarro-master = super.rivercarro.overrideAttrs (oa:
        {
          version = "master";
          src = rivercarro-src;
        }
      );


      # Commented out because need to update the patch
      # xorg = prev.xorg // {
      #   # Override xorgserver with patch to set x11 type
      #   xorgserver = lib.overrideDerivation prev.xorg.xorgserver (drv: {
      #     patches = drv.patches ++ [ ./x11-session-type.patch ];
      #   });
      # };

      inherit (import ../configs/editor.nix super neovim-flake.lib.neovimConfiguration)
        neovimJD;
      inherit (dwm-flake.packages.${system})
        dwmJD;
      inherit (emacs-config.packages.${system})
        emacs-jd;
      inherit (st-flake.packages.${system})
        stJD;
      weechatJD = super.weechat.override
        {
          configure = { availablePlugins, ... }: {
            scripts = with super.weechatScripts; [
              weechat-matrix
            ];
          };
        };
      agenix-cli = agenix.packages."${system}".default;
      inherit (deploy-rs.packages."${system}")
        deploy-rs;
      jdpkgs = jdpkgs.packages."${system}";
      bm-font = super.callPackage
        (secrets + "/bm")
        { };
      linux-doc = super.linux-doc.overrideAttrs
        (old: {
          nativeBuildInputs = old.nativeBuildInputs ++ [
            super.python3.pkgs.pyyaml
          ];
          postPatch = old.postPatch +
            ''
              patchShebangs \
                tools/net/ynl/ynl-gen-rst.py
            '';
        });
      ccid-udev = super.runCommand
        "ccid-udev"
        { }
        ''
          mkdir -p $out/lib/udev/rules.d/
          cp ${super.ccid}/lib/udev/rules.d/92_pcscd_ccid.rules $out/lib/udev/rules.d/
          sed -i '/Kobil/d' $out/lib/udev/rules.d/92_pcscd_ccid.rules
        '';

      inherit homeage
        impermanence;
    })
  ];
}
