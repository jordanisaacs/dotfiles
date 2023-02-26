{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.graphical.applications;
  isGraphical = let
    cfg = config.jd.graphical;
  in (cfg.xorg.enable == true || cfg.wayland.enable == true);
in {
  options.jd.graphical.applications.libreoffice = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable libreoffice with config [libreoffice]";
    };
  };

  config = mkIf (isGraphical && cfg.enable && cfg.libreoffice.enable) {
    # https://github.com/NixOS/nixpkgs/blob/9c2d391f0d403a67e68d432026037ed8dc3deb92/pkgs/applications/office/libreoffice/wrapper.sh#L21
    home.packages = [pkgs.libreoffice-fresh];
  };
}
