# Example for a fresh installation, never an in-place migration command.
# The caller must choose the disposable/new disk and a runtime password file.
{
  device,
  passwordFile,
  swapSize,
  espSize ? "550M",
}:
{
  disko.enableConfig = false;
  disko.devices.disk.installation = {
    type = "disk";
    inherit device;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          size = espSize;
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        swap = {
          priority = 2;
          size = swapSize;
          type = "8200";
          content = {
            type = "luks";
            name = "cryptswap";
            inherit passwordFile;
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
          priority = 3;
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            inherit passwordFile;
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
