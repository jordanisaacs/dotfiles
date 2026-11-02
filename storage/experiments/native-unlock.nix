# Inactive candidate, imported only by disposable VM tests. Do not activate on
# the laptop before its new credentials are enrolled and the change is approved.
{ mode }:
{ lib, ... }:
assert builtins.elem mode [
  "password"
  "key-filesystem"
];
{
  boot = {
    resumeDevice = "/dev/mapper/cryptswap";
    initrd = {
      supportedFilesystems = lib.optionals (mode == "key-filesystem") [ "ext2" ];
      luks.devices = {
        cryptroot = {
          device = "/dev/disk/by-label/NIXROOT";
          keyFile = lib.mkIf (mode == "key-filesystem") "/root.key:/dev/mapper/cryptkey";
        };
        cryptswap = {
          device = "/dev/disk/by-label/NIXSWAP";
          keyFile = lib.mkIf (mode == "key-filesystem") "/root.key:/dev/mapper/cryptkey";
        };
      }
      // lib.optionalAttrs (mode == "key-filesystem") {
        cryptkey.device = "/dev/disk/by-label/NIXKEY";
      };
    };
  };
  swapDevices = [ { device = "/dev/mapper/cryptswap"; } ];
}
