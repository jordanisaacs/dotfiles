{
  description = "System Config";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jdpkgs = {
      url = "github:jordanisaacs/jdpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim-flake = {
      url = "github:jordanisaacs/neovim-flake";
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

    dwl-flake = {
      url = "github:jordanisaacs/dwl-flake/updates";
    };

    homeage = {
      url = "github:jordanisaacs/homeage/activatecheck";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    extra-container = {
      url = "github:erikarvstedt/extra-container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";
    nur.url = "github:nix-community/NUR";
  };

  outputs = { nixpkgs, jdpkgs, home-manager, nur, neovim-flake, st-flake, dwm-flake, dwl-flake, homeage, extra-container, ... }@inputs:
    let
      inherit (nixpkgs) lib;

      util = import ./lib {
        inherit system pkgs home-manager lib overlays inputs;
      };

      scripts = import ./scripts {
        inherit pkgs lib;
      };

      inherit (import ./overlays {
        inherit system pkgs lib nur neovim-flake st-flake dwm-flake homeage scripts jdpkgs dwl-flake extra-container;
      }) overlays;

      inherit (util) user;
      inherit (util) host;

      pkgs = import nixpkgs {
        inherit system overlays;
        config = {
          permittedInsecurePackages = [
            "electron-9.4.4"
          ];
          allowUnfree = true;
        };
      };

      system = "x86_64-linux";

      defaultConfig = {
        core.enable = true;
        boot = "encrypted-efi";
        gnome = {
          enable = true;
          keyring = {
            enable = true;
          };
        };
        connectivity = {
          bluetooth.enable = true;
          sound.enable = true;
          printing.enable = true;
        };
        graphical = {
          xorg.enable = true;
          wayland = {
            enable = true;
            swaylock-pam = true;
          };
        };
        ssh.enable = true;
        extraContainer.enable = true;
      };

      desktopConfig = defaultConfig // {
        android.enable = true;
        windows.enable = true;
      };

      laptopConfig = defaultConfig // {
        laptop = {
          enable = true;
        };
      };

      frameworkConfig = laptopConfig // {
        framework = {
          enable = true;
          fprint = {
            enable = true;
          };
        };
        windows.enable = true;
      };

      defaultUser = [{
        name = "jd";
        groups = [ "wheel" "networkmanager" "video" "libvirtd" ];
        uid = 1000;
        shell = pkgs.zsh;
      }];

    in
    {
      installMedia = {
        kde = host.mkISO {
          name = "nixos";
          kernelPackage = pkgs.linuxPackages_latest;
          initrdMods = [ "xhci_pci" "ahci" "usb_storage" "sd_mod" "nvme" "usbhid" ];
          kernelMods = [ "kvm-intel" "kvm-amd" ];
          kernelParams = [ ];
          systemConfig = { };
        };
      };
      homeManagerConfigurations = {
        jd = user.mkHMUser {
          userConfig = {
            graphical = {
              applications = {
                enable = true;
                firefox.enable = true;
                libreoffice.enable = true;
              };
              wayland = {
                enable = true;
                type = "sway";
                background.enable = true;
                statusbar.enable = true;
                screenlock.enable = true;
              };
              xorg = {
                enable = true;
                type = "dwm";
                screenlock.enable = true;
              };
            };
            applications.enable = true;
            gpg.enable = true;
            git.enable = true;
            zsh.enable = true;
            ssh.enable = true;
            direnv.enable = true;
            weechat.enable = true;
            office365 = {
              enable = true;
              onedriver.enable = true; # pkg currently broken
            };
            wine = {
              enable = false; # wine things currently broken
              office365 = false;
            };
            keybase.enable = false;
            pijul.enable = true;
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
          kernelParams = [ ];
          kernelPatches = [ ];
          systemConfig = laptopConfig;
          users = defaultUser;
          cpuCores = 4;
        };

        framework = host.mkHost {
          name = "framework";
          NICs = [ "wlp170s0" ];
          kernelPackage = pkgs.linuxPackages_latest;
          initrdMods = [ "xhci_pci" "thunderbolt" "nvme" "usb_storage" "sd_mod" ];
          kernelMods = [ "kvm-intel" ];
          kernelParams = [ ];
          kernelPatches = [ ];
          systemConfig = frameworkConfig;
          users = defaultUser;
          cpuCores = 8;
          stateVersion = "21.11";
        };

        desktop = host.mkHost {
          name = "desktop";
          NICs = [ "enp6s0" "wlp5s0" ];
          kernelPackage = pkgs.linuxPackages_latest;
          initrdMods = [ "nvme" "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" ];
          kernelMods = [ "kvm-amd" ];
          kernelParams = [ ];
          kernelPatches = [ ];
          systemConfig = desktopConfig;
          users = defaultUser;
          cpuCores = 12;
          stateVersion = "21.11";
        };
      };
    };
}
