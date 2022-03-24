{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.windows;
in
{
  options.jd.windows.enable = mkOption {
    description = "Enable windows virtualisation";
    default = false;
    type = types.bool;
  };

  config = mkIf (cfg.enable) {
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        swtpm.enable = true;
        ovmf = {
          enable = true;
          package = pkgs.OVMFFull;
        };
      };
    };
    programs.dconf.enable = true;
    environment.systemPackages = with pkgs; [ virt-manager swtpm ];

  };
}
