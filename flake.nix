{
  description = "System Config";
  inputs = {
    # Package repositories
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jdpkgs = {
      url = "github:jordanisaacs/jdpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Extra nix/nixos modules
    dwarffs.url = "github:edolstra/dwarffs";
    impermanence.url = "github:nix-community/impermanence";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    simple-nixos-mailserver = {
      url = "gitlab:simple-nixos-mailserver/nixos-mailserver";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        utils.follows = "flake-utils";
      };
    };

    # Secrets
    secrets = {
      url = "git+ssh://git@github.com/jordanisaacs/secrets.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    homeage = {
      url = "github:jordanisaacs/homeage";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    microvm-nix = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    # Programs
    neovim-flake.url = "github:jordanisaacs/neovim-flake";

    emacs-config.url = "github:jordanisaacs/emacs-config";

    oxbow = {
      url = "github:3L0C/oxbow/v0.1.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      secrets,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;
      privateIdentifiers = secrets.dotfiles;

      util = import ./lib {
        inherit
          system
          pkgs
          home-manager
          lib
          inputs
          ;
      };

      scripts = import ./scripts { inherit pkgs; };
      style = import ./tests/style.nix { inherit pkgs; };
      treefmt = inputs.treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.ruff-format.enable = true;
      };

      inherit
        (import ./overlays {
          inherit
            system
            scripts
            secrets
            inputs
            ;
        })
        overlays
        ;

      inherit (util) user;
      inherit (util) host;
      inherit (util) utils;

      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system overlays;
        config = {
          allowUnfree = true;
        };
      };

      authorizedKeys = ''
        mail@jdisaacs.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKIspidvrzy1NFoUXMEs1A2Wpx3E8nxzCKGZfBXyezV
        jordan@snowytrees.dev ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKIspidvrzy1NFoUXMEs1A2Wpx3E8nxzCKGZfBXyezV
      '';

      authorizedKeyFiles = pkgs.writeTextFile {
        name = "authorizedKeys";
        text = authorizedKeys;
      };

      # wireguardConf = {
      #   enable = true;
      #   interface = "thevoid";
      #   peers = {
      #     intothevoid =
      #       let
      #         wgsecret = secrets.wireguard.intothevoid;
      #       in
      #       {
      #         wgAddrV4 = "10.55.1.1";
      #         inherit (wgsecret) publicKey;

      #         tags = [{ name = "net"; }];
      #       };

      #     chairlift =
      #       let
      #         wgsecret = secrets.wireguard.chairlift;
      #       in
      #       {
      #         wgAddrV4 = "10.55.0.2";
      #         interfaceMask = 16;
      #         listenPort = 51820;

      #         privateKeyPath = "/etc/wireguard/private_key";
      #         privateKeyAge = wgsecret.secret.file;
      #         inherit (wgsecret) publicKey;
      #         dns = "server";

      #         tags = [
      #           {
      #             name = "net";
      #             ipAddr = "5.161.103.90";
      #           }
      #         ];
      #       };

      #     framework =
      #       let
      #         wgsecret = secrets.wireguard.framework;
      #       in
      #       {
      #         wgAddrV4 = "10.55.1.2";
      #         interfaceMask = 16;
      #         listenPort = 51820;

      #         privateKeyPath = "/etc/wireguard/private_key";
      #         privateKeyAge = wgsecret.secret.file;
      #         inherit (wgsecret) publicKey;
      #         dns = "client";

      #         tags = [
      #           {
      #             name = "home";
      #             ipAddr = "172.26.40.247";
      #           }
      #           { name = "net"; }
      #         ];
      #       };

      #     desktop =
      #       let
      #         wgsecret = secrets.wireguard.desktop;
      #       in
      #       {
      #         wgAddrV4 = "10.55.0.1";
      #         interfaceMask = 16;
      #         listenPort = 51820;
      #         dns = "client";

      #         firewall = {
      #           allowedTCPPorts = [ 8080 ];
      #         };

      #         privateKeyPath = "/etc/wireguard/private_key";
      #         privateKeyAge = wgsecret.secret.file;
      #         inherit (wgsecret) publicKey;

      #         tags = [
      #           {
      #             name = "home";
      #             ipAddr = "172.26.26.90";
      #           }
      #           { name = "net"; }
      #         ];
      #       };
      #   };
      # };

      defaultUser = {
        name = "jd";
        groups = [ "wheel" ];
        uid = 1000;
      };

      defaultDesktopUser = defaultUser // {
        # Move plugdev to be auto-enabled
        groups = defaultUser.groups ++ [
          "video"
          "libvirtd"
          "plugdev"
        ];
      };

      defaultClientConfig = {
        core = {
          enable = true;
          ccache = true;
        };
        users.users = [ defaultDesktopUser ];
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
        networking = {
          firewall = {
            enable = true;
            allowKdeconnect = false;
            allowDefaultSyncthing = true;
          };
          wifi.enable = true;
          tailscale.enable = true;
        };
        kernel.watchdog = false;
        graphical = {
          enable = true;
          wayland = {
            enable = true;
            waylockPam = true;
          };
          # portals moved to home-manager so can't use nixos option
          # see https://github.com/nix-community/home-manager/issues/4621
          # flatpak.enable = true;
        };
        podman = {
          enable = true;
          users = [ "jd" ];
        };
        ssh = {
          enable = true;
          type = "client";
        };
        extraContainer.enable = false;
        debug = {
          enable = true;
          nixseparatedebuginfod.enable = true;
        };
        logitech.enable = true;
        qmk.enable = true;
      };

      frameworkConfig = utils.recursiveMerge [
        defaultClientConfig
        {
          boot.type = "uefi";
          fs.type = "encrypted-efi";
          initrd.plymouth = {
            enable = true;
            theme = "hexa_retro";
          };
          kernel = {
            initrdMods = [
              "xhci_pci"
              "thunderbolt"
              "nvme"
              "usb_storage"
              "sd_mod"
            ];
            mods = [ "kvm-intel" ];
          };
          laptop.enable = true;
          core.time = null;
          networking.wifi = {
            interface = "wifi0";
            permanentMACAddress = privateIdentifiers.wifi.permanentMACAddress;
            ipTime = true;
          };
          greetd.enable = true;
          framework = {
            enable = true;
            fprint = {
              enable = true;
            };
          };
          # wireguard = wireguardConf;
          # secrets.identityPaths = [ secrets.age.framework.system.privateKeyPath ];
          # secrets.identityPaths = [ "" ];

        }
      ];
    in
    {
      homeConfigurations =
        let
          mkHome =
            machineData:
            user.mkHMUser {
              inherit machineData;
              userConfig = {
                graphical = {
                  theme = "arc-dark";
                  applications = {
                    enable = true;
                    anki.enable = true;
                    cursor = {
                      enable = true;
                      scale = "1.5";
                    };
                    dolphin.enable = true;
                    firefox.enable = true;
                    libreoffice.enable = true;
                    multimedia.enable = true;
                    gaming.enable = true;
                    kdeconnect.enable = false;
                    gnome-keyring.enable = true;
                  };
                  wayland = {
                    enable = true;
                    type = "river";
                    background.enable = true;
                    statusbar.enable = true;
                    screenlock.enable = true;
                    screen.gamma = {
                      enable = true;
                      loc = "seattle";
                    };
                  };
                };
                applications = {
                  enable = true;
                  direnv.enable = true;
                  tldr.enable = true;
                  activitywatch.enable = true;
                  neomutt.enable = true;
                  neovim.enable = false;
                  lnav.enable = true;
                  tmux.enable = true;
                };
                shell = "bash";
                # secrets.identityPaths = [ secrets.age.framework.jd.privateKeyPath ];
                ssh.enable = true;
                gpg.enable = true;
                git = {
                  enable = true;
                  allowedSignerFile = builtins.toString authorizedKeyFiles;
                };
                weechat.enable = true;
                office365 = {
                  enable = false;
                  onedriver.enable = true; # pkg currently broken
                };
                wine = {
                  enable = false; # wine things currently broken
                  office365 = false;
                };
                keybase.enable = false;
                pijul.enable = true;
                kernel.enable = true;
              };
              username = "jd";
            };
          hostData =
            name:
            let
              host = self.nixosConfigurations.${name};
            in
            builtins.fromJSON host.config.environment.etc."hmsystemdata.json".text;
        in
        {
          jd = mkHome (hostData "framework");
          "jd@framework" = mkHome (hostData "framework");
        };

      # Other machines and installer definitions live in retired/outputs.nix.
      nixosConfigurations = {
        framework = host.mkHost {
          name = "framework";
          systemConfig = frameworkConfig;
          cpuCores = 8;
          stateVersion = "23.11";
          passthru =
            { config, lib, ... }:
            {
              # This interactive laptop must reach login without an access point.
              systemd.network.wait-online.enable = false;

              # The retired local finance service's data is intentionally
              # discarded, as requested. Re-enabling it removes this rule.
              systemd.tmpfiles.rules = lib.optionals (!config.jd.firefly-iii.enable) [
                "R! /var/lib/firefly-iii - - - -"
              ];
            };
        };
      };

      formatter.${system} = treefmt.config.build.wrapper;
      packages.${system}.home-manager = pkgs.home-manager;
      apps.${system}.home-manager = {
        type = "app";
        program = "${pkgs.home-manager}/bin/home-manager";
        meta.description = "Manage the user environment with Home Manager";
      };
      devShells.${system}.default = pkgs.mkShell {
        packages = style.devShellPackages ++ [ treefmt.config.build.wrapper ];
      };
      checks.${system} = style.checks // {
        formatting = treefmt.config.build.check self;
        framework = self.nixosConfigurations.framework.config.system.build.toplevel;
        home-framework = self.homeConfigurations."jd@framework".activationPackage;
        libreoffice-grammar = import ./tests/libreoffice-grammar.nix {
          inherit pkgs;
          home = self.homeConfigurations."jd@framework".config;
        };
        desktop-theme = import ./tests/desktop-theme.nix {
          inherit pkgs;
          home = self.homeConfigurations."jd@framework".config;
        };
        desktop-fonts = import ./tests/desktop-fonts.nix {
          inherit pkgs;
          home = self.homeConfigurations."jd@framework".config;
        };
        desktop-font-scaling = import ./tests/desktop-fonts.nix {
          inherit pkgs;
          # A second output policy must preserve the same preferred terminal
          # size through the actual generated Ghostty configuration.
          home =
            (self.homeConfigurations."jd@framework".extendModules {
              modules = [
                { jd.graphical.wayland.display.internalScale = lib.mkForce 1.5; }
              ];
            }).config;
        };
        firefox-sidebar = import ./tests/firefox-sidebar.nix {
          inherit pkgs;
          home = self.homeConfigurations."jd@framework".config;
        };
        wifi-migration = import ./tests/wifi-migration.nix { inherit pkgs; };
        wifi-boot = import ./tests/wifi-boot.nix { inherit pkgs; };
        initrd-dlopen = import ./tests/initrd-dlopen.nix { inherit pkgs; };
        xwayland-keymap = import ./tests/xwayland-keymap.nix { inherit pkgs; };
        dbus-policy =
          pkgs.runCommand "dbus-session-policy-tests"
            {
              nativeBuildInputs = [ pkgs.python3 ];
              DBUS_POLICY_NORMALIZER = pkgs.makeDBusConf.sessionPolicyNormalizer;
            }
            ''
              python -B ${./tests/test_dbus_policy.py}
              touch "$out"
            '';
        desktop-session = import ./tests/desktop-session.nix {
          inherit pkgs;
          homeConfiguration = self.homeConfigurations."jd@framework";
        };
        encrypted-boot = import ./tests/encrypted-boot.nix {
          inherit pkgs;
          bootMountOptions = self.nixosConfigurations.framework.config.fileSystems."/boot".options;
        };
        storage-password-boot = import ./tests/encrypted-storage-option.nix {
          inherit pkgs;
          mode = "password";
        };
        storage-disko-inventory = import ./tests/disko-inventory.nix {
          inherit pkgs nixpkgs;
          inherit (inputs) disko;
        };
        storage-disko-provision = import ./tests/disko-provision.nix {
          inherit pkgs;
          inherit (inputs) disko;
        };
        storage-key-filesystem-boot = import ./tests/encrypted-storage-option.nix {
          inherit pkgs;
          mode = "key-filesystem";
        };
        configuration-warnings =
          let
            warnings =
              self.nixosConfigurations.framework.config.warnings
              ++ self.homeConfigurations."jd@framework".config.warnings;
          in
          assert lib.assertMsg (warnings == [ ]) (
            "The framework configuration must evaluate without warnings:\n" + lib.concatStringsSep "\n" warnings
          );
          pkgs.runCommand "framework-configuration-warnings" { } "touch $out";
      };
    };
}
