{ config, lib, ... }:
{
  config = lib.mkIf config.jd.graphical.enable {
    # User-managed document portals still need the privileged FUSE helper.
    programs.fuse.enable = true;
  };
}
