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
      # Broken rstudio
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim-flake.url = "github:jordanisaacs/neovim-flake";

    st-flake = {
      url = "github:jordanisaacs/st-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    dwm-flake.url = "github:jordanisaacs/dwm-flake";

    dwl-flake.url = "github:jordanisaacs/dwl-flake/updates";

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

  outputs = { self, nixpkgs, jdpkgs, impermanence, deploy-rs, home-manager, nur, neovim-flake, st-flake, dwm-flake, dwl-flake, homeage, extra-container, ... }@inputs:
    let
      inherit (nixpkgs) lib;

      util = import ./lib {
        inherit system pkgs home-manager lib overlays inputs;
      };

      scripts = import ./scripts {
        inherit pkgs lib;
      };

      inherit (import ./overlays {
        inherit system pkgs lib nur neovim-flake st-flake dwm-flake
          homeage scripts jdpkgs dwl-flake extra-container
          impermanence deploy-rs;
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

      authorizedKeys = ''
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKIspidvrzy1NFoUXMEs1A2Wpx3E8nxzCKGZfBXyezV mail@jdisaacs.com
      '';

      authorizedKeyFiles = pkgs.writeTextFile {
        name = "authorizedKeys";
        text = authorizedKeys;
      };

      defaultServerConfig = {
        isQemuGuest = true;
        core.enable = true;
        boot = {
          type = "zfs";
          hostId = "2d360981";
          swapPartuuid = "52c2b662-0b7b-430c-9a10-068acbe9d15d";
        };
        ssh = {
          enable = true;
          type = "server";
          authorizedKeys = [ (builtins.toString authorizedKeys) ];
          initrdKeys = [ authorizedKeys ];
        };
        impermanence.enable = true;
      };

      defaultClientConfig = {
        core.enable = true;
        boot.type = "encrypted-efi";
        gnome = {
          enable = true;
          keyring = {
            enable = true;
          };
        };
        connectivity = {
          networkmanager.enable = true;
          bluetooth.enable = true;
          sound.enable = true;
          printing.enable = true;
          firewall.enable = true;
        };
        graphical = {
          xorg.enable = false;
          wayland = {
            enable = true;
            swaylock-pam = true;
          };
        };
        ssh = {
          enable = true;
          type = "client";
        };
        extraContainer.enable = true;
      };

      desktopConfig = defaultClientConfig // {
        android.enable = true;
        windows.enable = true;
        desktop.enable = true;
      };

      laptopConfig = defaultClientConfig // {
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

      defaultUser = {
        name = "jd";
        groups = [ "wheel" ];
        uid = 1000;
        shell = pkgs.zsh;
      };

      defaultUsers = [ defaultUser ];

      defaultDesktopUser = defaultUser // {
        groups = defaultUser.groups ++ [ "networkmanager" "video" "libvirtd" ];
      };
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
                enable = false;
                type = "dwm";
                screenlock.enable = true;
              };
            };
            applications.enable = true;
            gpg.enable = true;
            git = {
              enable = true;
              allowedSignerFile = builtins.toString authorizedKeyFiles;
            };
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
          users = defaultUsers;
          cpuCores = 4;
          stateVersion = "21.05";
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
          users = defaultUsers;
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
          users = defaultUsers;
          cpuCores = 12;
          stateVersion = "21.11";
        };

        chairlift = host.mkHost {
          name = "chairlift";
          NICs = [ "enp1s0" ];
          initrdMods = [ "sd_mod" "sr_mod" "ahci" "xhci_pci" ];
          kernelMods = [ ];
          kernelPackage = pkgs.linuxPackages_5_17;
          kernelParams = [ "nohibernate" ];
          kernelPatches = [ ];
          systemConfig = defaultServerConfig;
          users = [ defaultUser ];
          cpuCores = 2;
          stateVersion = "21.11";
        };

        # deploy.nodes.chairlift = {
        #   hostname = "5.161.103.90";
        #   sshOpts = [ "-p" "23" ];
        #   autoRollback = true;
        #   magicRollback = true;
        #   profiles = {
        #     system = {
        #       sshUser = "root";
        #       user = "root";
        #       path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.chairlift;
        #     };
        #   };
        # };

        # checks = builtins.mapAttrs
        #   (system: deployLib: deployLib.deployChecks self.deploy)
        #   deploy-rs.lib;
      };
    };
}

