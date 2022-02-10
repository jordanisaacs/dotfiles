{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.graphical;
in
{
  options.jd.graphical.applications = {
    enable = mkOption {
      type = types.bool;
      description = "Enable graphical applications";
    };
  };

  config = {
    home.packages = with pkgs; [ dolphin ];
  };
}
