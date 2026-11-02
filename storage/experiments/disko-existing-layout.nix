# Configuration-only inventory factory. No caller in the active laptop imports
# this. Even destroy=false does NOT make executing format/mount scripts safe.
{ device, partitionUUIDs }:
{
  disko.enableConfig = false;
  disko.devices.disk.framework = {
    type = "disk";
    inherit device;
    destroy = false;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          uuid = partitionUUIDs.ESP;
          label = "EFI system partition";
          size = "550M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        key = {
          priority = 2;
          uuid = partitionUUIDs.key;
          label = "cryptsetup luks key";
          size = "17M";
          content = {
            type = "luks";
            name = "cryptkey";
            extraFormatArgs = [
              "--label"
              "NIXKEY"
            ];
            # The current payload is raw key material, not a filesystem.
            content = null;
          };
        };
        swap = {
          priority = 3;
          uuid = partitionUUIDs.swap;
          label = "swap space (hibernation)";
          size = "33G";
          type = "8200";
          content = {
            type = "luks";
            name = "cryptswap";
            settings.keyFile = "/dev/mapper/cryptkey";
            extraFormatArgs = [
              "--label"
              "NIXSWAP"
            ];
            content = {
              type = "swap";
              resumeDevice = true;
              randomEncryption = false;
            };
          };
        };
        root = {
          priority = 4;
          uuid = partitionUUIDs.root;
          label = "root filesystem";
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            settings.keyFile = "/dev/mapper/cryptkey";
            extraFormatArgs = [
              "--label"
              "NIXROOT"
            ];
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
