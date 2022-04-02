{ inputs }:
{ pkgs, config, lib, ... }:
with lib;

let
  cfg = config.jd.core;
in
{
  options.jd.core = {
    enable = mkOption {
      description = "Enable core options";
      type = types.bool;
      default = true;
    };
  };

  config = mkIf (cfg.enable) {
    # Nix search paths/registries from:
    # https://github.com/gytis-ivaskevicius/flake-utils-plus/blob/166d6ebd9f0de03afc98060ac92cba9c71cfe550/lib/options.nix
    # Context thread: https://github.com/gytis-ivaskevicius/flake-utils-plus/blob/166d6ebd9f0de03afc98060ac92cba9c71cfe550/lib/options.nix
    environment.etc = mapAttrs'
      (name: value: {
        name = "nix/inputs/${name}";
        value = { source = value.outPath; };
      })
      inputs;

    nix =
      let
        flakes = filterAttrs
          (name: value: value ? outputs)
          inputs;
        flakesWithPkgs = filterAttrs
          (name: value:
            value.outputs ? legacyPackages || value.outputs ? packages)
          flakes;
        nixRegistry = builtins.mapAttrs (name: v: { flake = v; }) flakes;
      in
      {
        registry = nixRegistry;
        nixPath = mapAttrsToList
          (name: _: "${name}=/etc/nix/inputs/${name}")
          flakesWithPkgs;
        package = pkgs.nixUnstable;
        gc = {
          persistent = true;
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 14d";
        };
        extraOptions = ''
          keep-outputs = true
          keep-derivations = true
          experimental-features = nix-command flakes
        '';
      };

    environment.shells = [ pkgs.zsh pkgs.bash ];
    environment.pathsToLink = [ "/share/zsh" ];

    i18n.defaultLocale = "en_US.UTF-8";
    time.timeZone = "America/New_York";

    powerManagement.cpuFreqGovernor = lib.mkDefault "performance";
    hardware.enableRedistributableFirmware = lib.mkDefault true;

    environment.systemPackages = with pkgs; [
      # Shells
      zsh

      # Misc. Utilities
      exa
      gping
      inxi
      usbutils
      dnsutils
      neofetch
      unzip

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

      # Nix tools
      patchelf
      nix-index
      nix-tree
      manix

      # Text editor
      neovimJD

      # Scripts
      scripts.sysTools

      man-pages
      man-pages-posix
    ];

    security.sudo.extraConfig = "Defaults env_reset,timestamp_timeout=5";
    security.sudo.execWheelOnly = true;

    documentation = {
      enable = true;
      dev.enable = true;
      man = {
        enable = true;
        generateCaches = true;
      };
      info.enable = true;
      nixos.enable = true;
    };
  };
}
