{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.boot;
in {
  options.jd.boot = {
    type = mkOption {
      description = "Type of boot. Default encrypted-efi";
      default = null;
      type = types.enum ["encrypted-efi" "zfs" "zfs-v2"];
    };

    hostId = mkOption {
      # Generate with:
      # head -c4 /dev/urandom | od -A none -t x4
      description = "HostID, needed for server-zfs";
      default = null;
      type = types.str;
    };

    grubDevice = mkOption {
      description = "Grub device";
      default = null;
      type = types.str;
    };

    zfs = {
      userPool = mkEnableOption "a user pool";

      swap = {
        enable = mkEnableOption "zfs swap";

        swapPartuuid = mkOption {
          description = "Swap part uuid, needed for server-zfs";
          default = null;
          type = types.str;
        };
      };
    };
  };

  config = let
    bootConfig = mkMerge [
      (mkIf (cfg.type == "encrypted-efi") {
        environment.systemPackages = with pkgs; [e2fsprogs];
        fileSystems."/" = {
          device = "/dev/disk/by-label/DECRYPTNIXROOT";
          fsType = "ext4";
        };

        fileSystems."/boot" = {
          device = "/dev/disk/by-label/BOOT";
          fsType = "vfat";
        };

        swapDevices = [
          {device = "/dev/disk/by-label/DECRYPTNIXSWAP";}
        ];

        boot = {
          loader = {
            efi = {
              canTouchEfiVariables = true;
              efiSysMountPoint = "/boot";
            };

            grub = {
              enable = true;
              devices = ["nodev"];
              efiSupport = true;
              useOSProber = true;
              version = 2;
              extraEntries = ''
                menuentry "Reboot" {
                  reboot
                }
                menuentry "Power off" {
                  halt
                }
              '';
              extraConfig =
                if (config.jd.framework.enable)
                then "i915.enable_psr=0"
                else "";
            };
          };

          # plymouth.enable = true;
          initrd = {
            # systemd.enable = true;
            luks.devices = {
              cryptkey = {
                device = "/dev/disk/by-label/NIXKEY";
              };

              cryptroot = {
                device = "/dev/disk/by-label/NIXROOT";
                keyFile = "/dev/mapper/cryptkey";
              };

              cryptswap = {
                device = "/dev/disk/by-label/NIXSWAP";
                keyFile = "/dev/mapper/cryptkey";
              };
            };
          };
        };
      })

      # ZFS sources
      # https://nixos.wiki/wiki/ZFS
      # https://elis.nu/blog/2019/08/encrypted-zfs-mirror-with-mirrored-boot-on-nixos/
      # https://florianfranke.dev/posts/2020/03/installing-nixos-with-encrypted-zfs-on-a-netcup.de-root-server/
      (mkIf (cfg.type == "zfs" || cfg.type == "zfs-v2") {
        boot = {
          loader = {
            grub = {
              enable = true;
              version = 2;
              device = cfg.grubDevice;
              efiSupport = false;
            };
          };
          supportedFilesystems = ["zfs"];
          kernelParams = ["nohibernate"];
          zfs.requestEncryptionCredentials = true;
        };

        services.zfs.trim.enable = true;
        services.zfs.autoScrub.enable = true;
        services.zfs.autoScrub.pools = ["rpool"];

        networking.hostId = cfg.hostId;

        fileSystems."/boot" = {
          device = "/dev/disk/by-label/BOOT";
          fsType = "vfat";
        };

        swapDevices = lib.optional (cfg.zfs.swap.enable) {
          device = "/dev/disk/by-partuuid/${cfg.zfs.swap.swapPartuuid}";
          randomEncryption = true;
        };
      })
      (mkIf (cfg.type == "zfs-v2") (mkMerge [
        {
          jd.impermanence.rollbackDatasets = [
            "rpool/local"
            "rpool/local/root"
            "rpool/local/home"
          ];

          jd.impermanence.persistedDatasets = {
            "root" = {};
            "data" = {};
          };

          fileSystems."/" = {
            device = "rpool/local";
            fsType = "zfs";
          };

          fileSystems."/root" = {
            device = "rpool/local/root";
            fsType = "zfs";
          };

          fileSystems."/home" = {
            device = "rpool/local/home";
            fsType = "zfs";
          };

          fileSystems."/nix" = {
            device = "rpool/persist/nix";
            fsType = "zfs";
          };

          fileSystems."/persist/root" = {
            device = "rpool/persist/root";
            fsType = "zfs";
          };

          fileSystems."/persist/data" = {
            device = "rpool/persist/data";
            fsType = "zfs";
          };

          fileSystems."/backup/root" = {
            device = "rpool/backup/root";
            fsType = "zfs";
          };

          fileSystems."/backup/data" = {
            device = "rpool/backup/data";
            fsType = "zfs";
          };
        }
        (mkIf cfg.zfs.userPool {
          fileSystems."/home/jd" = {
            device = "rpool/local/home/jd";
            fsType = "zfs";
          };

          fileSystems."/persist/home/jd" = {
            device = "rpool/persist/home/jd";
            fsType = "zfs";
          };

          fileSystems."/backup/home/jd" = {
            device = "rpool/backup/home/jd";
            fsType = "zfs";
          };
        })
      ]))
      (mkIf (cfg.type == "zfs") {
        jd.impermanence.rollbackDatasets = [
          "rpool/local/root"
          "rpool/local/home"
        ];

        jd.impermanence.persistedDatasets = {
          "root" = {
            persist = "/persist";
            backup = "/persist";
          };
          "data" = {backup = "/persist/data";};
        };

        fileSystems."/" = {
          device = "rpool/local/root";
          fsType = "zfs";
        };

        fileSystems."/home" = {
          device = "rpool/local/home";
          fsType = "zfs";
        };

        fileSystems."/nix" = {
          device = "rpool/local/nix";
          fsType = "zfs";
          neededForBoot = true;
        };

        fileSystems."/persist" = {
          device = "rpool/persist/root";
          fsType = "zfs";
          neededForBoot = true;
        };

        fileSystems."/persist/home" = {
          device = "rpool/persist/home";
          fsType = "zfs";
          neededForBoot = true;
        };

        fileSystems."/persist/data" = {
          device = "rpool/persist/data";
          fsType = "zfs";
          neededForBoot = true;
        };
      })
    ];
  in
    bootConfig;
}
