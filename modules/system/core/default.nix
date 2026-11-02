{ inputs }:
{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.core;
in
{
  options.jd.keybindings = mkOption {
    type = types.enum [
      "vim"
      "emacs"
    ];
    default = "emacs";
    description = "Default editing and navigation keybinding profile, inherited by users.";
  };

  options.jd.core = {
    enable = mkOption {
      description = "Enable core options";
      type = types.bool;
      default = true;
    };

    time = mkOption {
      description = "Time zone (null if unmanaged)";
      type =
        with types;
        nullOr (enum [
          "west"
          "east"
        ]);
      default = "east";
    };

    ccache = mkOption {
      description = "Enable ccache";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    environment = {
      sessionVariables.JD_KEYBINDINGS = config.jd.keybindings;

      etc.inputrc.source = pkgs.writeText "inputrc" (
        "set editing-mode ${if config.jd.keybindings == "vim" then "vi" else "emacs"}\n"
        + builtins.readFile (inputs.nixpkgs + "/nixos/modules/programs/bash/inputrc")
      );

      sessionVariables = {
        EDITOR = "vim";
      };
      etc."nix/inputs/nixpkgs".source = inputs.nixpkgs.outPath;

      shells = [
        pkgs.zsh
        pkgs.bash
      ];
      # ZSH completions
      pathsToLink = [
        "/share/zsh"
        "/share/bash-completion"
      ];
      systemPackages = with pkgs; [
        # Misc.
        fastfetch
        bat
        util-linux

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
        gh
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
        neovim

        # Calculator
        bc
        bitwise

        # finders
        fd

        # Scripts
        jdScripts.sysTools

        # docs
        tldr
        man-pages
        man-pages-posix

        # file sending
        rclone
      ];
    };
    programs.zsh.interactiveShellInit =
      if config.jd.keybindings == "vim" then "bindkey -v" else "bindkey -e";

    i18n.defaultLocale = "en_US.UTF-8";
    console = {
      earlySetup = true;
      keyMap = "us";
      font = "ter-v32n";
      packages = with pkgs; [ terminus_font ];
    };

    time.timeZone =
      if cfg.time == null then
        null
      else
        (
          if (cfg.time == "east") then
            "US/Eastern"
          else
            (if cfg.time == "west" then "US/Pacific" else "Asia/Bangkok")
        );

    nix = {
      channel.enable = false;
      registry.nixpkgs.flake = inputs.nixpkgs;
      nixPath = [ "nixpkgs=/etc/nix/inputs/nixpkgs" ];
      package = pkgs.nixVersions.latest;
      gc = {
        persistent = true;
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 14d";
      };
      optimise.automatic = true;
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        keep-outputs = false;
        keep-derivations = true;
        sandbox = true;
        require-sigs = true;
        # Keep NixOS's default root-only daemon administration.
        substituters = [
          "https://nix-community.cachix.org"
          "https://nixpkgs-wayland.cachix.org"
          "https://eigenvalue.cachix.org"
        ];
        # NixOS supplies cache.nixos.org and its signing key.
        # Extra keys are published by nix-community.org/cache and the Cachix API.
        trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
          "eigenvalue.cachix.org-1:ykerQDDa55PGxU25CETy9wF6uVDpadGGXYrFNJA3TUs="
        ];
      };
    };

    security.sudo.extraConfig = "Defaults env_reset,timestamp_timeout=5";
    security.sudo.execWheelOnly = true;

    hardware.enableRedistributableFirmware = true;

    services = {
      udisks2.enable = true;

      fwupd.enable = true;

      dbus.implementation = "broker";

      journald.settings.Journal = {
        MaxRetentionSec = "1month";
        SystemMaxUse = "1G";
      };
    };

    programs.ccache.enable = cfg.ccache;

    documentation = {
      enable = true;
      dev.enable = true;
      man = {
        enable = true;
        cache.enable = true;
      };
      info.enable = true;
      nixos.enable = true;
    };
  };
}
