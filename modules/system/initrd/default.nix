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
      boot.initrd.verbose = mkDefault cfg.quiet;
    }
    (mkIf cfg.plymouth.enable {
      jd.kernel.quiet = mkDefault true;
      jd.kernel.disableBGRTRestore = mkDefault true;
      jd.initrd.quiet = mkDefault true;

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
