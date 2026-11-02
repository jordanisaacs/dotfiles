{ pkgs, mode }:
let
  pythonScript = import ../lib/python-script.nix { inherit pkgs; };
  prepare = pythonScript "prepare-storage-option" ./prepare-storage-option.py {
    inherit mode;
    cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
    cryptenroll = "${pkgs.systemd}/bin/systemd-cryptenroll";
    mkfsRoot = "${pkgs.e2fsprogs}/bin/mkfs.ext4";
    mkfsKey = "${pkgs.e2fsprogs}/bin/mkfs.ext2";
    mkswap = "${pkgs.util-linux}/bin/mkswap";
    mount = "${pkgs.util-linux}/bin/mount";
    umount = "${pkgs.util-linux}/bin/umount";
  };
in
pkgs.testers.runNixOSTest {
  name = "encrypted-storage-${mode}";
  nodes.machine = {
    virtualisation = {
      emptyDiskImages = [
        17
        128
        512
      ];
      useBootLoader = true;
      mountHostNixStore = true;
      useEFIBoot = true;
      memorySize = 1536;
      fileSystems."/boot".options = [ "umask=0077" ];
    };
    boot.loader.systemd-boot.enable = true;
    boot.kernelPackages = pkgs.linuxPackages_latest;
    environment.systemPackages = [ pkgs.cryptsetup ];
    specialisation.migrated.configuration = {
      imports = [ (import ../storage/experiments/native-unlock.nix { inherit mode; }) ];
      virtualisation = {
        useDefaultFilesystems = false;
        rootDevice = "/dev/mapper/cryptroot";
        fileSystems."/" = {
          device = "/dev/mapper/cryptroot";
          fsType = "ext4";
        };
      };
    };
  };
  testScript =
    { nodes, ... }:
    let
      migrated = nodes.machine.specialisation.migrated.configuration.system.build.toplevel;
    in
    ''
      from datetime import timedelta
      import json

      machine.wait_for_unit("multi-user.target")
      machine.succeed("${prepare}/bin/prepare-storage-option")
      machine.succeed("${migrated}/bin/switch-to-configuration boot")
      machine.succeed("sync")
      machine.crash()
      machine.start()
      machine.wait_for_console_text("Please enter passphrase for disk", timeout=timedelta(seconds=40))
      # A single entry must unlock both volumes through the native cache or
      # the native read-only key-device filesystem mechanism.
      machine.send_console("Vm-fixture-4caD9!r3-Passphrase\n")
      machine.wait_for_console_text("Reached target Multi-User System", timeout=timedelta(seconds=60))
      machine.wait_for_unit("multi-user.target")
      root = machine.succeed("findmnt --noheadings --output SOURCE /").strip()
      assert root == "/dev/mapper/cryptroot", root
      machine.succeed("grep -q 'Existing root data survived' /migration-sentinel")
      for name in ("cryptroot", "cryptswap"):
          machine.succeed("systemctl is-active dev-mapper-" + name + ".device")
      swaps = machine.succeed("cat /proc/swaps")
      swap_device = machine.succeed("readlink -f /dev/mapper/cryptswap").strip()
      assert swap_device in {line.split()[0] for line in swaps.splitlines()[1:]}, swaps
      metadata = json.loads(machine.succeed("cat /migration-keyslots.json"))
      assert all(len(slots) >= 2 for slots in metadata.values()), metadata
      if "${mode}" == "password":
          machine.fail("test -e /dev/mapper/cryptkey")
      else:
          properties = machine.succeed("udevadm info --query=property --name=/dev/mapper/cryptkey")
          assert "ID_FS_USAGE=filesystem" in properties, properties
          assert "SYSTEMD_READY=0" not in properties, properties
      journal = machine.succeed("journalctl -b --no-pager --output=json")
      records = [json.loads(line) for line in journal.splitlines()]
      def events(unit, prefix):
          return [int(r["__MONOTONIC_TIMESTAMP"]) for r in records
                  if r.get("UNIT") == unit and r.get("MESSAGE", "").startswith(prefix)]
      resume = events("systemd-hibernate-resume.service", "Finished")
      mounting_root = events("sysroot.mount", "Mounting")
      assert resume and mounting_root, [(r.get("UNIT"), r.get("MESSAGE")) for r in records
                                       if "hibernate-resume" in str(r.get("UNIT")) or r.get("UNIT") == "sysroot.mount"]
      assert max(resume) < min(mounting_root), (resume, mounting_root)
    '';
}
