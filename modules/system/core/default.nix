{ inputs
, patchedPkgs
,
}: { pkgs
   , config
   , lib
   , ...
   }:
with lib; let
  cfg = config.jd.core;
in
{
  options.jd.core = {
    enable = mkOption {
      description = "Enable core options";
      type = types.bool;
      default = true;
    };

    time = mkOption {
      description = "Time zone (null if unmanaged)";
      type = with types; nullOr (enum [ "west" "east" ]);
      default = "east";
    };

    ccache = mkOption {
      description = "Enable ccache";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    i18n.defaultLocale = "en_US.UTF-8";
    console = {
      earlySetup = true;
      keyMap = "us";
      font = "ter-v32n";
      packages = with pkgs; [ terminus_font ];
    };

    time.timeZone =
      if cfg.time == null
      then null
      else
        (
          if (cfg.time == "east")
          then "US/Eastern"
          else
            (
              if cfg.time == "west"
              then "US/Pacific"
              else "Asia/Bangkok"
            )
        );

    # Nix search paths/registries from:
    # https://github.com/gytis-ivaskevicius/flake-utils-plus/blob/166d6ebd9f0de03afc98060ac92cba9c71cfe550/lib/options.nix
    # Context thread: https://github.com/gytis-ivaskevicius/flake-utils-plus/blob/166d6ebd9f0de03afc98060ac92cba9c71cfe550/lib/options.nix
    nix =
      let
        flakes =
          filterAttrs
            (name: value: value ? outputs)
            inputs;
        flakesWithPkgs =
          filterAttrs
            (name: value:
              value.outputs ? legacyPackages || value.outputs ? packages)
            flakes;
        nixRegistry = builtins.mapAttrs (name: v: { flake = v; }) flakes;
      in
      {
        registry = nixRegistry;
        nixPath =
          mapAttrsToList
            (name: _: "${name}=/etc/nix/inputs/${name}")
            flakesWithPkgs;
        package = pkgs.nixUnstable;
        gc = {
          persistent = true;
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 14d";
        };
        optimise.automatic = true;
        extraOptions = ''
          keep-outputs = false
          keep-derivations = true
          experimental-features = nix-command flakes
        '';
        settings = {
          auto-optimise-store = true;
          # For nixpkgs-wayland: https://github.com/nix-community/nixpkgs-wayland#flake-usage
          substituters = [
            "https://cache.nixos.org"
            "https://nixpkgs-wayland.cachix.org"
            "https://eigenvalue.cachix.org"
          ];
          trusted-public-keys = [
            "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
            "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
            "eigenvalue.cachix.org-1:ykerQDDa55PGxU25CETy9wF6uVDpadGGXYrFNJA3TUs="
          ];
        };
      };

    environment = {
      sessionVariables = {
        EDITOR = "vim";
      };
      etc =
        mapAttrs'
          (name: value: {
            name = "nix/inputs/${name}";
            value = {
              source =
                if name == "nixpkgs"
                then patchedPkgs.outPath
                else value.outPath;
            };
          })
          inputs;

      shells = [ pkgs.zsh pkgs.bash ];
      # ZSH completions
      pathsToLink = [ "/share/zsh" "/share/bash-completion" ];
      systemPackages = with pkgs; [
        # Misc.
        neofetch
        bat
        utillinux

        # Shells
        zsh

        # Files
        unzip
        lsof

        # Benchmarking
        hyperfine # benchmark multiple runs of commands

        # Hardware
        inxi # system information tool
        usbutils # tools for usb
        pciutils # tools for pci utils
        hwloc # topology

        # Kernel
        systeroid

        # Network
        gping # ping with graph
        iftop # bandwith usage on interface
        tcpdump # packet analyzer
        nmap # scan remote ports/networks
        hping # tcp/ip packet assembler & analyzer
        traceroute # track route taken by packets
        ipcalc # ip network calculator

        lm_sensors

        # DNS
        dnsutils
        dnstop

        # secrets
        rage
        agenix-cli
        pass

        # Processors
        jq
        htmlq
        dasel

        ripgrep
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

        # version ocntrol
        git
        git-lfs
        git-filter-repo
        difftastic

        # Nix tools
        patchelf
        nix-index
        nix-tree
        nix-diff
        nix-prefetch
        # deploy-rs
        manix
        comma

        # Text editor
        vim

        # Calculator
        bc
        bitwise

        # Scripts
        scripts.sysTools

        # docs
        tldr
        man-pages
        man-pages-posix

        # file sending
        rclone
      ];
    };

    security.sudo.extraConfig = "Defaults env_reset,timestamp_timeout=5";
    security.sudo.execWheelOnly = true;

    hardware.enableRedistributableFirmware = true;

    services.udisks2.enable = true;
    services.fwupd.enable = true;

    programs.ccache.enable = cfg.ccache;

    services.dbus.implementation = "broker";

    services.journald.extraConfig = ''
      MaxRetentionSec=1month
      SystemMaxUse=1G
    '';

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
