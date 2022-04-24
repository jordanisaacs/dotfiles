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

    (final: prev:
      let
        # Temporary calibre override:
        # https://github.com/NixOS/nixpkgs/issues/167626
        packageOverrides = (pyFinal: pyPrev: {
          apsw = pyPrev.apsw.overridePythonAttrs (oldAttrs: {
            version = "3.38.1-r1";
            src = prev.fetchFromGitHub {
              owner = "rogerbinns";
              repo = "apsw";
              rev = "3.38.1-r1";
              sha256 = "sha256-pbb6wCu1T1mPlgoydB1Y1AKv+kToGkdVUjiom2vTqf4=";
            };
            checkInputs = [ ];
            # Project uses custom test setup to exclude some tests by default, so using pytest
            # requires more maintenance
            # https://github.com/rogerbinns/apsw/issues/335
            checkPhase = ''
              python tests.py
            '';
            pytestFlagsArray = [ ];
            disabledTests = [ ];
          });
        });
        pythonC = prev.python3.override { inherit packageOverrides; };
        calibre = prev.calibre.override { python3Packages = pythonC.pkgs; };
      in
      {
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

        agenix = agenix.defaultPackage."${system}";
        deploy-rs = deploy-rs.packages."${system}".deploy-rs;
        jdpkgs = jdpkgs.packages."${system}";
        inherit homeage extra-container impermanence calibre;
      })
  ];
}
