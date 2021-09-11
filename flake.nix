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
      inherit system pkgs home-manager lib; overlays = (pkgs.overlays);
    };

    inherit (util) user;
    inherit (util) host;

    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [
        nur.overlay
        neovim-flake.overlay."${system}"
        (final: prev: { # Version of xss-lock that supports logind SetLockedHint
          xss-lock = prev.xss-lock.overrideAttrs (old: {
            src = prev.fetchFromGitHub {
              owner = "xdbob";
              repo = "xss-lock";
              rev = "7b0b4dc83ff3716fd3051e6abf9709ddc434e985";
              sha256 = "TG/H2dGncXfdTDZkAY0XAbZ80R1wOgufeOmVL9yJpSk=";
            };
          });
          xorg = prev.xorg // { # Override xorgserver with patch to set x11 type
            xorgserver = lib.overrideDerivation prev.xorg.xorgserver (drv: {
              patches = drv.patches ++ [ ./x11-session-type.patch ];
            });
          };
          dwmJD = dwm-flake.packages.${system}.dwmJD;
          stJD = st-flake.packages.${system}.stJD;
        })
      ];
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
          keyring = {
            enable = true;
            gui.enable = true;
          };
          connectivity = {
            wifi.enable = false;
            bluetooth.enable = true;
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
