{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.jd.graphical.wayland;
  inherit (cfg) display;
  # Home Manager exposes native includes, but not Kanshi's newer ...output
  # directive. It lets the same profile work with any number of external
  # displays without changing their scale, mode, position, or enabled state.
  profile = pkgs.writeText "kanshi-internal-display.conf" ''
    profile internal-display {
      output ${builtins.toJSON display.internalOutput}
      ...output "*"
    }
  '';
in
{
  options.jd.graphical.wayland.display = {
    enable = lib.mkEnableOption "automatic per-output display configuration" // {
      default = config.machineData.systemConfig.laptop.enable or false;
    };
    internalOutput = lib.mkOption {
      type = lib.types.str;
      default = "eDP-1";
      description = "Kanshi output name or manufacturer/model/serial criteria for the internal panel.";
    };
    internalScale = lib.mkOption {
      type = lib.types.numbers.positive;
      default = 1.25;
      description = ''
        Physical pixels per logical pixel on the internal panel. This scales
        all Wayland UI, rather than only text. Terminal font size compensates
        for this factor to preserve its preferred physical size; Fuzzel uses
        physical DPI independently. External outputs keep their current scale.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && display.enable) {
    services.kanshi = {
      enable = true;
      systemdTarget = "graphical-session.target";
      settings = [
        {
          output = {
            criteria = display.internalOutput;
            scale = display.internalScale;
          };
        }
        { include = toString profile; }
      ];
    };
  };
}
