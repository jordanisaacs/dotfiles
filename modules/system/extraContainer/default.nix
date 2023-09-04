{ pkgs
, config
, lib
, ...
}:
with lib; {
  options.jd.extraContainer = {
    enable = mkOption {
      description = "Enable extra-container";
      type = types.bool;
      default = false;
    };
  };
}
