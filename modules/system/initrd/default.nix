{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.initrd;

in
{
  options.jd.initrd = {
    plymouth = {
      enable = mkEnableOption "enable plymouth";
      theme = mkOption {
        description = "plymouth theme";
        default = "lone";
        type = types.enum [
          "lone"
          "hexa_retro"
        ];
      };
    };

    quiet = mkEnableOption "quiet initrd";
  };

  config = mkMerge [
    {
      # systemd is the only supported initrd implementation.

      boot.kernelParams = optionals cfg.quiet [
        "rd.udev.log_level=3"
        "rd.systemd.show_status=false"
      ];
    }
    (mkIf cfg.plymouth.enable {
      jd = {
        kernel.quiet = mkDefault true;
        initrd.quiet = mkDefault true;
      };

      # nixpkgs enables this unit in stage 1 only. The stage-2 daemon must
      # change root before its surviving DRM helper is started at shutdown.
      # Keep the native Plymouth command and readiness conditions.
      systemd.services.plymouth-switch-root-initramfs = {
        wantedBy = [
          "halt.target"
          "kexec.target"
          "poweroff.target"
          "reboot.target"
        ];
        after = [ "generate-shutdown-ramfs.service" ];
        before = [ "shutdown.target" ];
      };

      # The helper execs after Plymouth chroots into the shutdown RAMFS. Its
      # executable and ELF dependencies must live there, rather than pinning
      # /oldroot/nix/store until poweroff or losing the retained splash.
      systemd.shutdownRamfs.storePaths = [
        "${config.boot.plymouth.package}/libexec/plymouth/plymouthd-fd-escrow"
      ];

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
