{
  config,
  lib,
  pkgs,
  ...
}:
# Raw encrypted key volumes require explicit readiness after systemd's
# unformatted-device check: https://github.com/NixOS/nixpkgs/issues/527478
let
  readinessRule = pkgs.writeTextFile {
    name = "cryptkey-readiness";
    destination = "/lib/udev/rules.d/99-z-cryptkey-ready.rules";
    text = ''
      # cryptkey intentionally contains raw key bytes, not a filesystem.
      # systemd's 99-systemd.rules marks such unlocked mappings unready.
      # Only publish our completed key mapping; leave other dm devices alone.
      ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="dm-*", ENV{DM_NAME}=="cryptkey", ENV{DM_UUID}=="CRYPT-LUKS*", ENV{DM_UDEV_DISABLE_OTHER_RULES_FLAG}!="1", ENV{ID_PART_TABLE_TYPE}=="", ENV{ID_FS_USAGE}=="", ENV{SYSTEMD_READY}="1"
    '';
  };
in
{
  config = lib.mkIf (config.jd.fs.type == "encrypted-efi") {
    boot.initrd.services.udev.packages = [ readinessRule ];
    # Preserve readiness after switch-root and subsequent device re-probes.
    services.udev.packages = [ readinessRule ];
  };
}
