{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.jd.kernel;
in {
  options.jd.kernel = {
    package = mkOption {
      description = "Kernel package, may be overriden internally. eg for zfs";
      default = pkgs.linuxPackages_latest;
      type = types.raw;
    };

    initrdMods = mkOption {
      description = "List of initrd kernel modules";
      default = [];
      type = with types; listOf str;
    };

    mods = mkOption {
      description = "List of kernel modules";
      default = [];
      type = with types; listOf str;
    };

    quiet = mkEnableOption "quiet kernel console on boot";

    # https://bugzilla.redhat.com/show_bug.cgi?id=1718564
    # 1) UEFI shows logo
    # 2) grub
    # 3) kernel restores logo
    # 4) spinner theme without logo
    # So you get the logo twice, which I agree is ugly.
    # You can tell the kernel to skip step 3. by adding video=efifb:nobgrt on the kernel commandline to disable it.
    # https://hansdegoede.livejournal.com/20632.html
    # https://patchwork.kernel.org/project/linux-fbdev/patch/20180912091235.20473-1-hdegoede@redhat.com/``
    disableBGRTRestore = mkEnableOption "Disable restoring the bgrt logo";
  };

  config.boot = {
    initrd.availableKernelModules = cfg.initrdMods;

    kernelPackages = mkDefault cfg.package;
    kernelModules = cfg.mods;

    # use rd because systemd
    kernelParams = ["boot.shell_on_fail"] ++ optionals cfg.quiet ["quiet" "rd.udev.log_level=3"] ++ optional cfg.disableBGRTRestore "video=efifb:nobgrt";
  };
}
