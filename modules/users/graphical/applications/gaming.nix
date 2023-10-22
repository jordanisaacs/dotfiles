{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.graphical.applications;
  isGraphical =
    let
      cfg = config.jd.graphical;
    in
    cfg.xorg.enable || cfg.wayland.enable;

  retroArch = pkgs.retroarch.override {
    cores = with pkgs.libretro; [
      dolphin
      citra
    ];
  };

  steam = pkgs.steam.override (prev: {
    extraLibraries = pkgs:
      let
        prevLibs = if prev ? extraLibraries then prev.extraLibraries pkgs else [ ];
        additionalLibs = with pkgs;
          if stdenv.hostPlatform.is64bit
          then [ pkgs.mesa.drivers ] ++ [
            intel-media-driver
            libvdpau-va-gl
            vaapiIntel
          ]
          else [ ];
      in
      prevLibs ++ additionalLibs;
  });

  steam-gamescope = pkgs.writeShellScriptBin "steam-gamescope" ''
    gamescope --steam -- steam -tenfoot -pipewire-dmabuf
  '';
in
{
  options.jd.graphical.applications.gaming = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable gaming packages";
    };
  };

  config = mkIf (isGraphical && cfg.enable && cfg.gaming.enable) {
    home.packages = [
      retroArch
      steam
      steam.run
      pkgs.gamescope
      steam-gamescope
    ];
  };
}
