{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.ssh;
in {
  options.jd.ssh = {
    enable = mkOption {
      description = "Whether to enable ssh";
      type = types.bool;
      default = false;
    };

    type = mkOption {
      description = "Whether is SSH client or server";
      type = types.enum ["client" "server"];
      default = "client";
    };

    authorizedKeys = mkOption {
      description = "Authorized ssh keys";
      type = types.listOf types.str;
    };

    initrdKeys = mkOption {
      description = "SSH key for initrd";
      type = types.listOf types.str;
    };

    ports = mkOption {
      default = [23];
      type = with types; listOf port;
      description = "SSH ports";
    };

    firewall = mkOption {
      type = types.enum ["world" "wg"];
      description = "Open firewall to everyone or wireguard";
    };

    hostKeyAge = mkOption {
      type = types.path;
      description = "Encrypted SSH host key file";
    };

    hostKeyPath = mkOption {
      default = "/etc/ssh/host_private_key";
      type = types.path;
      description = "Path to decrypted SSH key";
    };
  };

  config = mkMerge [
    (mkIf (cfg.type == "client") {
      # programs.ssh.startAgent = true;
    })
    (mkIf (cfg.type == "server") (mkMerge [
      (mkIf (cfg.firewall == "world") {
        services.openssh.openFirewall = true;
      })
      (mkIf
        (cfg.firewall == "wg" && (assertMsg config.jd.wireguard.enable "Wireguard must be enabled for wireguard ssh firewall")) {
          services.openssh.openFirewall = false;
          networking.firewall.interfaces.${config.jd.wireguard.interface}.allowedTCPPorts = cfg.ports;
        })

      {
        services.openssh = {
          enable = true;
          ports = cfg.ports;
          hostKeys = [];
          settings = {
            PasswordAuthentication = false;
          };
          extraConfig = ''
            PubkeyAuthentication yes

            HostKey ${cfg.hostKeyPath}
          '';
        };

        # terminfo's for correct formatting of ssh terminal
        environment.systemPackages = [
          pkgs.foot.terminfo
        ];

        age.secrets.ssh_host_private_key = {
          file = cfg.hostKeyAge;
          path = cfg.hostKeyPath;
          mode = "600";
        };

        users.users.root = {
          openssh.authorizedKeys.keys = cfg.authorizedKeys;
        };
      }

      (mkIf (config.jd.boot.type == "zfs") {
        boot.initrd.network = {
          # Disable if bootstrapped because keys are not yet created
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
      })
    ]))
  ];
}
