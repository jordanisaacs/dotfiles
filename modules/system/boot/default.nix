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
      type = types.enum ["encrypted-efi" "zfs"];
    };

    hostId = mkOption {
      description = "HostID, needed for server-zfs";
      default = null;
      type = types.str;
    };

    swapPartuuid = mkOption {
      description = "Swap part uuid, needed for server-zfs";
      default = null;
      type = types.str;
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
      # Cannot create subvolumes until it is mounted,
      # If iso does not have bcachefs
      (let
        # todo: hardcode
        device = "/dev/vda1";

        unlock = device: ''
          ds="${device}"
          while [ $success -eq 0 ]; do
            ${systemd}/bin/systemd-ask-password "Enter key: for $ds" | ${bcachefs-tools}/bin/bcachefs unlock "$ds" \
              && success=1
          done
        '';
      in
        mkIf (cfg.type == "bcachefs-bootstrap" || cfg.type == "bcachefs")
        {
          boot = {
            loader = {
              efi = {
                canTouchEfiVariables = true;
                efiSysMountPoint = "/boot";
              };
              systemd-boot = {
                enable = true;
                efiSupport = false;
              };
            };
            supportedFilesystems = ["bcachefs"];
            kernelParams = ["nohibernate"];
            initrd.systemd = {
              enable = true;
              extraBin = {
              };
            };
          };

          fileSystems."/" = {
            inherit device;
            fsType = "bcachefs";
          };
        })
      # ZFS sources
      # https://nixos.wiki/wiki/ZFS
      # https://elis.nu/blog/2019/08/encrypted-zfs-mirror-with-mirrored-boot-on-nixos/
      # https://florianfranke.dev/posts/2020/03/installing-nixos-with-encrypted-zfs-on-a-netcup.de-root-server/
      (
        mkIf (cfg.type == "zfs") {
          boot = {
            loader = {
              grub = {
                enable = true;
                version = 2;
                device = "/dev/sda";
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

          swapDevices = [
            {
              device = "/dev/disk/by-partuuid/${cfg.swapPartuuid}";
              randomEncryption = true;
            }
          ];

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
        }
      )
    ];
  in
    bootConfig;
}
