{ pkgs, config, lib, ... }:
# https://nixos.wiki/wiki/GNOME#Running_GNOME_programs_outside_of_GNOME
with lib;
let
  cfg = config.jd.sops;
  sops = if cfg.enable then pkgs.sops-nix.nixosModules.sops else null;
in
{
  options.jd.sops = {
    enable = mkOption {
      description = "Enable sops programs";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf (cfg.enable) {
    environment.systemPackages = with pkgs; [ age ];
  };
}

