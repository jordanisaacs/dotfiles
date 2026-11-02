{ config, lib, ... }:
{
  options.jd.graphical.wayland.touchpad.scrollFactor = lib.mkOption {
    type = lib.types.numbers.positive;
    default = if config.machineData.systemConfig.laptop.enable or false then 0.5 else 1.0;
    description = ''
      Multiplier for touchpad scroll distance. Laptop sessions use half the
      compositor's native scroll distance; mouse wheels retain their defaults.
    '';
  };
}
