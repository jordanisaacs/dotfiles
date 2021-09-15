{
  description = "System Config";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim-flake = {
      url = "github:jordanisaacs/neovim-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    st-flake = {
      url = "github:jordanisaacs/st-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    dwm-flake = {
      url = "github:jordanisaacs/dwm-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    flake-utils.url = "github:numtide/flake-utils";
    nur.url = "github:nix-community/NUR";
  };

  outputs = { nixpkgs, home-manager, nur, neovim-flake, st-flake, dwm-flake, ... }@inputs:
  let
    inherit (nixpkgs) lib;

    util = import ./lib {
      inherit system pkgs home-manager lib; inherit overlays;
    };

    scripts = import ./scripts {
      inherit pkgs lib;
    };

    inherit (import ./pkgs {
      inherit pkgs;
    }) myPkgs;

    inherit (import ./overlays {
      inherit system pkgs lib nur neovim-flake st-flake dwm-flake scripts myPkgs;
    }) overlays;

    inherit (util) user;
    inherit (util) host;

    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      inherit overlays;
    };

    system = "x86_64-linux";

  in {
    homeManagerConfigurations = {
      jd = user.mkHMUser {
        userConfig = {
          desktop = {
            type = "dwm";
            screenlock.enable = true;
          };
          applications.enable = true;
          gpg.enable = true;
          git.enable = true;
          zsh.enable = true;
          ssh = {
            enable = true;
            kerberos.enable = true;
          };
        };
        username = "jd";
      };
    };

    nixosConfigurations = {
      laptop = host.mkHost {
        name = "laptop";
        NICs = [ "enp0s31f6" "wlp2s0" ];
        kernelPackage = pkgs.linuxPackages;
        initrdMods = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" "rtsx_pci_sdmmc" ];
        kernelMods = [ "kvm-intel" ];
        kernelParams = [];
        systemConfig = {
          core.enable = true;
          boot = "encrypted-efi";
          laptop = {
            enable = true;
          };
          gnome = {
            enable = true;
            keyring = {
              enable = true;
              gui.enable = true;
            };
          };
          connectivity = {
            bluetooth.enable = true;
            sound.enable = true;
            printing.enable = true;
          };
          xserver = {
            enable = true;
            display-manager = {
              type = "startx";
            };
          };
        };
        users = [{
          name = "jd";
          groups = [ "wheel" "networkmanager" "video" ];
          uid = 1000;
          shell = pkgs.zsh;
        }];
        cpuCores = 4;
      };
    };
  };
}
