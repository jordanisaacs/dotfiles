# Dotfiles

My NixOS dotfiles for both system and users (home-manager).

## Follow Along

Follow along with my NixOS evolution and things I learn along the way: [NixOS Desktop Series](https://jdisaacs.com/series/nixos-desktop/)

## Custom Flakes

[jdpkgs](https://github.com/jordanisaacs/jdpkgs): A variety of programs that I have packaged and/or created useful wrappers for.

[neovim-flake](https://github.com/jordanisaacs/neovim-flake): A configurable flake for noevim.

## Some Gems

Working GTK/QT theming, icons, and cursors on wayland. See *./modules/users/graphical/shared.nix*.

Mounted on login onedrive filesystem using [onedriver](https://github.com/jstaf/onedriver) and a systemd-unit. See *./modules/users/office365/default.nix*

A working `x11` (using `startx` and patched `xserver` to support idle-action) and `wayland` setup on `tty1` and `tty2` respectively. See *./modules/users/graphical/*

## Credit

Based on Wil Taylor's [dotfiles](https://github.com/wiltaylor/dotfiles). Would not have the setup I have today without his [youtube series](https://www.youtube.com/watch?v=QKoQ1gKJY5A&list=PL-saUBvIJzOkjAw_vOac75v-x6EzNzZq-) and repo as a guide.

