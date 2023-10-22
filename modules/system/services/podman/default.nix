{ config
, lib
, pkgs
, ...
}:
with lib; let
  cfg = config.jd.podman;
in
{
  options.jd.podman = {
    enable = mkEnableOption "podman with rootless support";

    users = mkOption {
      description = "Users to enable rootless podman for";
      type = with types; listOf (enum (builtins.map (u: u.name) config.jd.users.users));
      default = [ ];
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ slirp4netns fuse-overlayfs ];

    virtualisation.podman = {
      enable = true;
      autoPrune.enable = true;
      autoPrune.dates = "weekly";

      dockerSocket.enable = true;
      dockerCompat = true;
    };

    users.users = genAttrs cfg.users (_: {
      autoSubUidGidRange = true;
    });
  };
}
