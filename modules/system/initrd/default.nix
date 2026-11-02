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

      boot.kernelParams = optional cfg.quiet "rd.udev.log_level=3";
    }
    (mkIf cfg.plymouth.enable {
      jd = {
        kernel.quiet = mkDefault true;
        initrd.quiet = mkDefault true;
      };

      # NixOS enables the shutdown unit and Plymouth provides the conditions.
      # Keep only the ordering that its generic dracut/mkinitcpio unit lacks.
      systemd.services.plymouth-switch-root-initramfs.after = [
        "generate-shutdown-ramfs.service"
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
