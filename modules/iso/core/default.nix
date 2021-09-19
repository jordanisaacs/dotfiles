{config, pkgs, lib, modulesPath, ...}:
{
  system.stateVersion = "20.09";

  nix = {
    extraOptions = "experimental-features = nix-command flakes";
    gc = {
      automatic = true;
      options = "--delete-older-than 5d";
    };
    package = pkgs.nixFlakes;
  };

  # Make this config a iso config
  imports = [ "${modulesPath}/installer/cd-dvd/iso-image.nix" ];

  networking.networkmanager.enable = true;
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;

  powerManagement.cpuFreqGovernor = lib.mkDefault "performance";
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  environment.systemPackages = with pkgs; [
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
