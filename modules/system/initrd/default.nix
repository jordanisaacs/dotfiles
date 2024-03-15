{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.initrd;

  systemd = config.systemd.package;

  gpgService = {
    description = "GPG agent";
    after = [
      "systemd-modules-load.service"
      "systemd-ask-password-console.service"
    ];
  };
in
{
  options.jd.initrd = {
    plymouth = {
      enable = mkEnableOption "enable plymouth";
      theme = mkOption {
        description = "plymouth theme";
        default = "lone";
        type = types.enum [ "lone" "hexa_retro" ];
      };
    };

    quiet = mkEnableOption "quiet initrd";
  };

  config = mkMerge [
    {
      boot.initrd.systemd.enable = true;

      # Does not matter for systemd
      # boot.initrd.verbose = mkDefault cfg.quiet;

      # Debug, needs bashInteractive due to how services are generated
      boot.initrd.systemd.additionalUpstreamUnits = [ "debug-shell.service" ];
      boot.kernelParams = (optional cfg.quiet "rd.udev.log_level=3") ++ [ "rd.systemd.debug_shell=1" ];
      boot.initrd.systemd.storePaths = [ "${pkgs.bashInteractive}/bin/bash" ];
    }
    # (mkIf cfg.gpg.enable {
    #   boot.initrd.systemd = {
    #     extraBin.pinentry = "${pkgs.systemd-pinentry}/bin/systemd-pinentry";
    #   };
    # })
    (mkIf cfg.plymouth.enable {
      jd = {
        kernel.quiet = mkDefault true;
        kernel.disableBGRTRestore = mkDefault true;
        initrd.quiet = mkDefault true;
      };


      systemd.services.plymouth-switch-root-initramfs = {
        wantedBy = [ "halt.target" "kexec.target" "plymouth-switch-root-initramfs.service" "poweroff.target" "reboot.target" ];
        unitConfig.After = [ "generate-shutdown-ramfs.service" ];
        unitConfig.ConditionPathExists = [ "" "/run/initramfs/shutdown" ];
      };

      boot.plymouth = {
        enable = true;
        inherit (cfg.plymouth) theme;
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
