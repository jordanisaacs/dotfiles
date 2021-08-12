{ config, pkgs, lib, ... }:
let
  scripts = import ./scripts.nix { inherit pkgs; };
in {
  nix = {
    extraOptions = "experimental-features = nix-command flakes";
    gc = {
      automatic = true;
      options = "--delete-older-than 5d";
    };
    
    package = pkgs.nixUnstable;
  };
  
  environment.shells = [ pkgs.zsh pkgs.bash ];

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "America/Los_Angeles";

  environment.variables = {
    MOZ_USE_XINPUT2 = "1";
  };

  powerManagement.cpuFreqGovernor = lib.mkDefault "performance";
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  environment.systemPackages = with pkgs; [
    wget
    curl
    zsh
    neofetch
    pstree
    htop
    acpi

    git
    git-crypt

    nix-index
    manix

    neovimJD

    scripts.sysTool
  ];

  security.sudo.extraConfig = "Defaults env_reset,timestamp_timeout=5";
  security.sudo.execWheelOnly = true;
}
