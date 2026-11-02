{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.graphical.applications;
  isGraphical =
    let
      cfg = config.jd.graphical;
    in
    cfg.wayland.enable;

  pythonScript = import ../../../../lib/python-script.nix { inherit pkgs; };
  steam-gamescope = pythonScript "steam-gamescope" ../../../../scripts/desktop.py {
    action = "command";
    command = [
      "${pkgs.gamescope}/bin/gamescope"
      "--steam"
      "--"
      "${pkgs.steam}/bin/steam"
      "-tenfoot"
      "-pipewire-dmabuf"
    ];
  };
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
      # retroArch [was coredumping :(]
      # The upstream Steam runtime reads the system's 64/32-bit graphics
      # environments; do not maintain a second, hardware-specific driver list.
      pkgs.steam
      pkgs.steam.run
      pkgs.gamescope
      steam-gamescope
    ];
  };
}
