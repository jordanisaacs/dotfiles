{
  pkgs,
  withFix ? true,
  bootMountOptions ? [ ],
}:
let
  inherit (pkgs) lib;
  # Public fixture credentials: these never touch the laptop's real disks.
  passphrase = pkgs.writeText "vm-luks-passphrase" "vm-only-passphrase";
  prepare =
    pkgs.writers.writePython3Bin "prepare-encrypted-boot-fixture"
      {
        flakeIgnore = [ "E501" ];
      }
      ''
        import os
        from pathlib import Path
        import subprocess

        cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup"


        def run(*arguments):
            subprocess.run(arguments, check=True)


        def format_volume(device, label, key):
            run(cryptsetup, "luksFormat", "--batch-mode", "--type", "luks2",
                "--label", label, "--pbkdf", "pbkdf2",
                "--pbkdf-force-iterations", "1000", "--key-file", key, device)


        format_volume("/dev/vdb", "NIXKEY", "${passphrase}")
        run(cryptsetup, "open", "--key-file", "${passphrase}", "/dev/vdb", "cryptkey")
        # Match the laptop: a 17 MiB LUKS2 container has a 1 MiB raw key payload.
        with Path("/dev/mapper/cryptkey").open("wb", buffering=0) as key:
            key.write(os.urandom(1024 * 1024))
            os.fsync(key.fileno())
        for device, label, name in [
            ("/dev/vdc", "NIXSWAP", "cryptswap"),
            ("/dev/vdd", "NIXROOT", "cryptroot"),
        ]:
            format_volume(device, label, "/dev/mapper/cryptkey")
            run(cryptsetup, "open", "--key-file", "/dev/mapper/cryptkey", device, name)
        run("${pkgs.e2fsprogs}/bin/mkfs.ext4", "/dev/mapper/cryptroot")
        run("${pkgs.util-linux}/bin/mkswap", "/dev/mapper/cryptswap")
      '';
in
pkgs.testers.runNixOSTest {
  name = "chained-luks-boot";
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
      # qemu-vm replaces the filesystem declarations to use its disposable ESP.
      # Keep the laptop's mount permissions while replacing only the device.
      fileSystems."/boot".options = bootMountOptions;
    };
    boot.loader.systemd-boot.enable = true;
    boot.initrd.systemd.emergencyAccess = true;
    environment.systemPackages = [ pkgs.cryptsetup ];

    specialisation.encrypted.configuration = {
      # Exercise the real encrypted-efi declarations and the exact production
      # compatibility rule, rather than another copy of their configuration.
      imports = [
        ../modules/system/fs
        (
          { lib, ... }:
          {
            # Unused ZFS branches refer to this sibling module's option.
            options.jd.impermanence = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
          }
        )
      ];
      disabledModules = lib.optional (!withFix) ../modules/system/fs/cryptkey-readiness.nix;
      jd.fs.type = "encrypted-efi";
      # qemu-vm otherwise replaces all production LUKS devices with {}.
      virtualisation = {
        useDefaultFilesystems = false;
        rootDevice = "/dev/mapper/cryptroot";
        fileSystems."/" = {
          device = "/dev/mapper/cryptroot";
          fsType = "ext4";
        };
      };
      boot.initrd.systemd.services.encrypted-boot-observer = {
        unitConfig.DefaultDependencies = false;
        requires = [ "systemd-cryptsetup@cryptkey.service" ];
        after = [ "systemd-cryptsetup@cryptkey.service" ];
        wantedBy = [ "initrd.target" ];
        serviceConfig = {
          Type = "oneshot";
          StandardOutput = "journal+console";
          ExecStart = [
            "/bin/udevadm settle"
            "/bin/systemctl show systemd-cryptsetup@cryptkey.service dev-mapper-cryptkey.device --property=Id --property=ActiveState --property=SubState"
            "/bin/udevadm info --query=property --name=/dev/mapper/cryptkey"
          ];
        };
      };
    };
  };
  testScript =
    { nodes, ... }:
    let
      encrypted = nodes.machine.specialisation.encrypted.configuration.system.build.toplevel;
    in
    ''
      from datetime import timedelta

      machine.wait_for_unit("multi-user.target")
      machine.succeed("${prepare}/bin/prepare-encrypted-boot-fixture")
      machine.succeed("${encrypted}/bin/switch-to-configuration boot")
      machine.succeed("sync")
      machine.crash()

      machine.start()
      machine.wait_for_console_text("Please enter passphrase for disk cryptkey")
      machine.send_console("vm-only-passphrase\n")
      if ${if withFix then "False" else "True"}:
          machine.wait_for_console_text("SYSTEMD_READY=0", timeout=timedelta(seconds=30))
          console = machine.get_console_log()
          assert "ActiveState=active" in console, console
          assert "ActiveState=inactive" in console, console
      machine.wait_for_console_text(
          "Reached target Multi-User System", timeout=timedelta(seconds=60)
      )
      machine.wait_for_unit("multi-user.target")
      machine.succeed("systemctl is-active dev-mapper-cryptkey.device")
      machine.succeed("systemctl is-active dev-mapper-cryptroot.device")
      machine.succeed("systemctl is-active dev-mapper-cryptswap.device")
      root = machine.succeed("findmnt --noheadings --output SOURCE /").strip()
      assert root == "/dev/mapper/cryptroot", root
      boot_mode = machine.succeed("stat --format=%a /boot").strip()
      assert boot_mode == "700", boot_mode
      swaps = machine.succeed("cat /proc/swaps")
      swap_device = machine.succeed("readlink -f /dev/mapper/cryptswap").strip()
      assert swap_device in {line.split()[0] for line in swaps.splitlines()[1:]}, swaps
      properties = machine.succeed(
          "udevadm info --query=property --name=/dev/mapper/cryptkey"
      )
      assert "SYSTEMD_READY=1" in properties, properties
      key_device = machine.succeed("readlink -f /dev/mapper/cryptkey").strip().rsplit("/", 1)[1]
      machine.succeed(
          "udevadm trigger --settle --action=change /sys/class/block/" + key_device
      )
      properties = machine.succeed(
          "udevadm info --query=property --name=/dev/mapper/cryptkey"
      )
      assert "SYSTEMD_READY=1" in properties, properties
      for name in ("cryptkey", "cryptroot", "cryptswap"):
          machine.succeed("systemctl is-active dev-mapper-" + name + ".device")
    '';
}
