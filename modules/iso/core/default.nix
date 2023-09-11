{ config
, pkgs
, lib
, modulesPath
, ...
}:
with lib;
{
  # Make this config a iso config
  imports = [ "${modulesPath}/installer/cd-dvd/iso-image.nix" ];

  options.jd = {
    airgap = mkEnableOption "networking";
  };

  config = mkMerge [
    (mkIf config.jd.airgap {
      # Disable networking so the system is air-gapped
      # Comment all of these lines out if you'll need internet access
      boot.initrd.network.enable = false;
      networking.dhcpcd.enable = false;
      networking.dhcpcd.allowInterfaces = [ ];
      networking.interfaces = { };
      networking.firewall.enable = true;
      networking.useDHCP = false;
      networking.useNetworkd = false;
      networking.wireless.enable = false;
      networking.networkmanager.enable = lib.mkForce false;
    })
    (mkIf (!config.jd.airgap) {
      networking.networkmanager.enable = true;
    })
    {
      system.stateVersion = "23.11";

      nix = {
        extraOptions = "experimental-features = nix-command flakes";
        gc = {
          automatic = true;
          options = "--delete-older-than 5d";
        };
        package = pkgs.nixFlakes;
      };

      # Always copytoram so that, if the image is booted from, e.g., a
      # USB stick, nothing is mistakenly written to persistent storage.
      boot.kernelParams = [ "copytoram" ];

      # Secure defaults
      boot.tmp.cleanOnBoot = true;
      # https://www.suse.com/support/kb/doc/?id=000020545
      boot.kernel.sysctl = { "kernel.unprivileged_bpf_disabled" = 1; };

      boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

      boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usb_storage" "sd_mod" "nvme" "usbhid" ];
      boot.kernelModules = [ "kvm-intel" "kvm-amd" ];

      boot.supportedFilesystems = [ "zfs" ];
      networking.hostId = "f6734914";

      isoImage.makeEfiBootable = true;
      isoImage.makeUsbBootable = true;

      powerManagement.cpuFreqGovernor = lib.mkDefault "performance";
      hardware.enableRedistributableFirmware = lib.mkDefault true;

      environment.systemPackages = with pkgs;
        [
          wget
          pciutils
          curl
          bind
          killall
          dmidecode
          neofetch
          htop
          bat
          unzip
          file
          zip
          p7zip
          strace
          ltrace

          # Setup script(s)
          scripts.setupTools

          # text editor
          neovimJD

          # vcs tools
          git
          git-crypt

          # File tools
          cryptsetup
          gptfdisk
          zsh
          iotop
          nvme-cli

          pstree
          acpi
          nix-index
        ];
    }
  ];
}
