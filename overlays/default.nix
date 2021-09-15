{ pkgs, nur, dwm-flake, neovim-flake, st-flake, scripts, system, lib, myPkgs }:
{
  overlays = [
    nur.overlay
    neovim-flake.overlay."${system}"
    scripts.overlay
    (final: prev: { # Version of xss-lock that supports logind SetLockedHint
      xss-lock = prev.xss-lock.overrideAttrs (old: {
        src = prev.fetchFromGitHub {
          owner = "xdbob";
          repo = "xss-lock";
          rev = "7b0b4dc83ff3716fd3051e6abf9709ddc434e985";
          sha256 = "TG/H2dGncXfdTDZkAY0XAbZ80R1wOgufeOmVL9yJpSk=";
        };
      });
      xorg = prev.xorg // { # Override xorgserver with patch to set x11 type
        xorgserver = lib.overrideDerivation prev.xorg.xorgserver (drv: {
          patches = drv.patches ++ [ ./x11-session-type.patch ];
        });
      };
      dwmJD = dwm-flake.packages.${system}.dwmJD;
      stJD = st-flake.packages.${system}.stJD;
      inherit myPkgs;
    })
  ];
}
