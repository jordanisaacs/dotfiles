{ pkgs, config, lib, ... }:
with lib;

{
  config.jd.graphical.applications = {
    enable = false;
    firefox.enable = false;
    libreoffice.enable = false;
  };
}
