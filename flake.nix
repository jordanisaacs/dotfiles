{
  description = "System Config";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    
    home-manager.url = "github:nix-community/home-manager/release-21.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    neovim-flake = {
      url = "github:jordanisaacs/neovim-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    flake-utils.url = "github:numtide/flake-utils";
    nur.url = "github:nix-community/NUR";
  };

  outputs = { nixpkgs, home-manager, nur, neovim-flake, ... }@inputs:
  let
    inherit (nixpkgs) lib;
    inherit (lib) attrValues;

    util = import ./lib { inherit system pkgs home-manager lib; overlays = (pkgs.overlays); };

    inherit (util) user;
    inherit (util) host;

    pkgs = import nixpkgs {
      inherit system;
      config = { allowUnfree = true; };
      overlays = [
        nur.overlay
        neovim-flake.overlay."${system}"
      ];
    };

    system = "x86_64-linux";

  in {
    homeManagerConfigurations = {
      jd = user.mkHMUser {
        roles = [ "git" "alacritty" "gpg" "applications" ];
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
        roles = [ "efi" "core" "kde" ];
        users = [{
          name = "jd";
          groups = [ "wheel" "networkmanager" ];
          uid = 1000;
          shell = pkgs.zsh;
        }];
        cpuCores = 4;
        laptop = true;
      };
    };
  };
}
