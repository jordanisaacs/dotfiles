{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.windows;
in
{
  options.jd.windows.enable = mkOption {
    description = "Enable windows virtualisation";
    default = false;
    type = types.bool;
  };

  config = mkIf cfg.enable {
    virtualisation.libvirtd = {
      enable = true;

      onShutdown = "suspend";
      onBoot = "ignore";

      qemu = {
        package = pkgs.qemu;

        swtpm.enable = true;
        ovmf = {
          enable = true;
          packages = [ pkgs.OVMFFull.fd ];
        };

        runAsRoot = true;
      };
    };

    environment = {
      systemPackages = mkIf config.jd.graphical.enable [
        pkgs.virt-manager
        pkgs.swtpm
      ];

      etc = {
        "ovmf/edk2-x86_64-secure-code.fd" = {
          source = "${config.virtualisation.libvirtd.qemu.package}/share/qemu/edk2-x86_64-secure-code.fd";
        };

        "ovmf/edk2-i386-vars.fd" = {
          source = "${config.virtualisation.libvirtd.qemu.package}/share/qemu/edk2-i386-vars.fd";
          mode = "0644";
          user = "libvirtd";
        };
      };
    };
  };
}
