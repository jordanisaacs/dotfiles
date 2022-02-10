{ pkgs, ... }:
with pkgs;
{
  myPkgs = {
    lssecret = callPackage ./lssecret.nix { };
    onedriver = callPackage ./onedriver.nix { };
    weechat-matrix-rs = callPackage ./weechat-matrix-rs.nix { };
    zsh-vi-mode = callPackage ./zsh-vi-mode.nix { };
    volantes-cursors = callPackage ./volantes-cursors.nix { };
    la-capitaine-icon-theme = callPackage ./la-capitaine-icon-theme { };
  };
}
