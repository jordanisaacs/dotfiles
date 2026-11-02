{
  system,
  secrets,
  scripts,
  inputs,
}:
{
  overlays = [
    (import ./dbus-policy.nix)
    (import ./gawk-info.nix)
    (import ./initrd-dlopen.nix)
    (import ./xwayland-keymap.nix)
    (import ./gamescope-errors.nix)
    (import ./libreoffice-wrapper.nix)
    (import ./tlaplus-toolbox.nix)
    (import ./mission-center.nix)
    (import ./screencast.nix)
    (import ./river-channel.nix)
    (import ./river-vt-lifecycle.nix)
    scripts.overlay
    inputs.nur.overlays.default
    inputs.oxbow.overlays.default
    inputs.reka.overlays.default
    (import ./river-health.nix)

    (_self: super: {
      inherit (import ../configs/editor.nix super inputs.neovim-flake.lib.neovimConfiguration)
        neovimJD
        ;
      emacs-jd = import ./emacs.nix {
        editor = inputs.emacs-config;
        inherit system;
      };
      weechatJD = super.weechat.override {
        configure = _: {
          scripts = with super.weechatScripts; [ weechat-matrix ];
        };
      };
      home-manager = inputs.home-manager.packages.${system}.home-manager;
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
