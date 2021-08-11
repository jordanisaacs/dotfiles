{ pkgs, config, lib, ... }:
{
  home.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" ]; })    
  ];
}
