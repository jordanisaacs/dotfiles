{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.android;
in
{
  options.jd.android.enable = mkOption {
    description = "Type of boot. Default encrypted-efi";
    default = false;
    type = types.bool;
  };

  config = mkIf (cfg.enable) {

    # https://wiki.archlinux.org/title/Waydroid#Using_binderfs
    # https://nixos.wiki/wiki/Linux_kernel#Custom_configuration
    virtualisation.waydroid.enable = true;
  };
}
