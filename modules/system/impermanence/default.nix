{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.jd.impermanence;
in
{
  options.jd.impermanence = {
    enable = mkOption {
      description = "Whether to enable impermanence";
      type = types.bool;
      default = false;
    };

    type = mkOption {
      description = "Whether is SSH client or server";
      type = types.enum [ "client" "server" ];
      default = "client";
    };

    authorizedKeyFiles = mkOption {
      description = "Authorized ssh keys";
      type = types.listOf types.str;
      default = "";
    };
  };

  config =
    let
      impermanence = mkMerge [
        (mkIf (config.jd.boot.type == "zfs") {
          # Erase zfs pools on boot
          boot.initrd.postDeviceCommands = lib.mkAfter ''
            zfs rollback -r rpool/local/root@blank
            zfs rollback -r rpool/local/home@blank
          '';

          environment.persistence."/persist".directories = mkIf (config.jd.ssh.enable && config.jd.ssh.type == "server") [
            "/etc/secrets/initrd"
          ];
        })
        (mkIf (config.jd.ssh.enable) {
          environment.persistence."/persist".directories = [
            "/etc/ssh"
          ];
        })
        ({
          environment.persistence."/persist" = {
            hideMounts = true;
            directories = [
              # secret key directory
              "/etc/age"
            ];
          };
        })
      ];
    in
    mkIf cfg.enable impermanence;
}
