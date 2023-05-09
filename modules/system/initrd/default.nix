{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.initrd;
in {
  options.jd.initrd = {
    plymouth = {
      enable = mkEnableOption "enable plymouth";
      theme = mkOption {
        description = "plymouth theme";
        default = "lone";
        type = types.enum ["lone" "hexa_retro"];
      };
    };

    quiet = mkEnableOption "quiet initrd";
  };

  config = mkMerge [
    {
      boot.initrd.systemd.enable = true;
      boot.kernelParams = optionals cfg.quiet ["rd.udev.log_level=3"];

      # Does not matter for systemd
      # boot.initrd.verbose = mkDefault cfg.quiet;

      # Debug, needs bashInteractive due to how services are generated
      # boot.initrd.systemd.additionalUpstreamUnits = ["debug-shell.service"];
      # boot.kernelParams = ["rd.systemd.debug_shell=1"];
      # boot.initrd.systemd.storePaths = ["${pkgs.bashInteractive}/bin/bash"];
    }
    (mkIf cfg.plymouth.enable {
      jd.kernel.quiet = mkDefault true;
      jd.kernel.disableBGRTRestore = mkDefault true;
      jd.initrd.quiet = mkDefault true;

      systemd.services.plymouth-switch-root-initramfs.wantedBy = ["halt.target" "kexec.target" "plymouth-switch-root-initramfs.service" "poweroff.target" "reboot.target"];
      systemd.services.plymouth-switch-root-initramfs.unitConfig.After = ["generate-shutdown-ramfs.service"];
      systemd.services.plymouth-switch-root-initramfs.unitConfig.ConditionPathExists = ["" "/run/initramfs/shutdown"];

      boot.plymouth = {
        enable = true;
        theme = cfg.plymouth.theme;
        font = "${pkgs.bm-font}/share/fonts/truetype/BerkeleyMono-Regular.ttf";

        themePackages = [
          (pkgs.stdenv.mkDerivation {
            name = "plymouth-theme-${cfg.plymouth.theme}";
            src = ./plymouth-themes + "/${cfg.plymouth.theme}.tar.gz";
            installPhase = ''
              runHook preInstall

              mkdir $out/share/plymouth/themes/${cfg.plymouth.theme} -p
              chmod +w -R $out/share/plymouth
              cp -r ./ $out/share/plymouth/themes/${cfg.plymouth.theme}/
              chmod +w $out -R
              find $out -type f | while read file; do
                sed -i 's;/usr/share/plymouth;/etc/plymouth;g' "$file"
              done

              runHook postInstall
            '';
          })
        ];
      };
    })
  ];
}
