{ pkgs
, config
, lib
, ...
}:
with lib; let
  cfg = config.jd.kernel;
in
{
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.machineData.systemConfig.podman.enable;
        message = "To enable podman for user, it must be enabled for system";
      }
    ];

    xdg.configFile."containers/storage.conf".text = ''
      [storage]
      driver = "overlay"

      [storage.options.overlay]
      mount_program = "${pkgs.fuse-overlayfs}/bin/fuse-overlayfs"
    '';
  };
}
