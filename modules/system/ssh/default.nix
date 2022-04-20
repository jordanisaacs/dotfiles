{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.jd.ssh;
in
{
  options.jd.ssh = {
    enable = mkOption {
      description = "Whether to enable ssh";
      type = types.bool;
      default = false;
    };

    type = mkOption {
      description = "Whether is SSH client or server";
      type = types.enum [ "client" "server" ];
      default = "client";
    };

    authorizedKeys = mkOption {
      description = "Authorized ssh keys";
      type = types.listOf types.str;
      default = [ "" ];
    };

    initrdKeys = mkOption {
      description = "SSH key for initrd";
      default = null;
      type = types.listOf types.str;
    };
  };

  config =
    let
      client = {
        programs.ssh.startAgent = true;
      };

      server = mkMerge [
        ({
          services.openssh = {
            enable = true;
            ports = [ 23 ];
          };

          # terminfo's for correct formatting of ssh terminal
          environment.systemPackages = [
            pkgs.foot.terminfo
          ];

          users.users.root = {
            openssh.authorizedKeys.keys = cfg.authorizedKeys;
          };
        })
        (mkIf (config.jd.boot.type == "zfs") {
          boot.initrd = {
            network = {
              enable = true;
              ssh = {
                enable = true;
                port = 2323;
                hostKeys = [
                  "/etc/secrets/initrd/ssh_host_ed25519_key"
                ];
                authorizedKeys = cfg.initrdKeys;
              };
              postCommands = ''
                cat <<EOF > /root/.profile
                if pgrep -x "zfs" > /dev/null
                then
                  zfs load-key -a
                  killall zfs
                else
                  echo "zfs not running -- maybe the pool is taking time to load for unforseen reasons"
                fi
                EOF
              '';
            };
          };
        })
      ];

      ssh = if (cfg.type == "client") then client else server;
    in
    server;
}
