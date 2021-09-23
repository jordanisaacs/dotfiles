{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.core;
in {
  options.jd.core = {
    enable = mkOption {
      description = "Enable core options";
      type = types.bool;
      default = true;
    };
  };

  config = mkIf (cfg.enable) {
    nix = {
      package = pkgs.nixUnstable;
      extraOptions = "experimental-features = nix-command flakes";
      gc = {
        automatic = true;
        options = "--delete-older-than 5d";
      };
    };

    environment.shells = [ pkgs.zsh pkgs.bash ];

    i18n.defaultLocale = "en_US.UTF-8";
    time.timeZone = "America/New_York";

    powerManagement.cpuFreqGovernor = lib.mkDefault "performance";
    hardware.enableRedistributableFirmware = lib.mkDefault true;

    environment.systemPackages = with pkgs; [
      unzip
      neofetch

      # Shells
      zsh

      # Processors
      jq
      gawk
      gnused

      # Downloaders
      wget
      curl

      # system monitors
      bottom
      htop
      acpi
      pstree

      # Graphics
      libva-utils
      vdpauinfo
      glxinfo

      # version ocntrol
      git
      git-crypt

      # Nix tools
      patchelf
      nix-index
      manix

      # Text editor
      neovimJD

      # Scripts
      scripts.sysTools
    ];

    fonts.fonts = with pkgs; [
      carlito
    ];

    security.sudo.extraConfig = "Defaults env_reset,timestamp_timeout=5";
    security.sudo.execWheelOnly = true;
  };
}
