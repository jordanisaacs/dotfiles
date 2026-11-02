# Retired machine and installer definitions, retained for reference only.
# This file is deliberately not imported by flake.nix. The server definitions
# need PostgreSQL and systemd-initrd migrations before they can be deployed again.
# Shared client defaults and the Home Manager constructor remain in flake.nix;
# pass them explicitly if restoring an archived configuration.
{
  inputs,
  system,
  host,
  utils,
  authorizedKeys,
  defaultClientConfig,
  mkHome,
}:
let
  defaultServerConfig = {
    core.enable = true;
    boot.type = "bios";
    fs.type = "zfs";
    users.mutableUsers = false;
    ssh = {
      enable = true;
      type = "server";
      authorizedKeys = [ (builtins.toString authorizedKeys) ];
      initrdKeys = [ authorizedKeys ];
    };
    networking = {
      firewall.enable = true;
    };
    impermanence.enable = true;
  };

  gondolaConfig = utils.recursiveMerge [
    defaultServerConfig
    {
      # users.rootPassword = secrets.passwords.gondola;
      isQemuGuest = true;
      boot.grubDevice = "/dev/vda";
      kernel.initrdMods = [
        "sr_mod"
        "ata_piix"
        "virtio_pci"
        "virtio_scsi"
        "virtio_blk"
        "virtio_net"
      ];

      fs.hostId = "fe120267";

      # secrets.identityPaths = [ secrets.age.gondola.privateKeyPath ];
      networking = {
        static = {
          enable = true;
          interface = "ens3";
          ipv6.addr = "2001:550:5a00:550b::1/64";
          ipv4.addr = "38.45.64.210/32";
          ipv4.gateway = "38.45.64.1";
        };
      };
      ssh = {
        firewall = "world";
        # hostKeyAge = secrets.ssh.host.gondola.secret.file;
      };
    }
  ];

  chairliftConfig = utils.recursiveMerge [
    defaultServerConfig
    {
      # users.rootPassword = secrets.passwords.chairlift;
      isQemuGuest = true;
      boot.grubDevice = "/dev/sda";
      kernel.initrdMods = [
        "sd_mod"
        "sr_mod"
        "ahci"
        "xhci_pci"
      ];
      fs = {
        hostId = "2d360981";
        zfs.swap = {
          swapPartuuid = "52c2b662-0b7b-430c-9a10-068acbe9d15d";
          enable = true;
        };
      };
      # secrets.identityPaths = [ secrets.age.chairlift.privateKeyPath ];
      # wireguard = wireguardConf;
      networking = {
        static = {
          enable = true;
          interface = "enp1s0";
          ipv6.addr = "2a01:4ff:f0:865b::1/64";
          ipv4 = {
            addr = "5.161.103.90/32";
            gateway = "172.31.1.1";
            onlink = true;
          };
        };
      };
      ssh = {
        firewall = "wg";
        # hostKeyAge = secrets.ssh.host.chairlift.secret.file;
      };
      # acme.email = secrets.acme.email;
      monitoring.enable = false;
      microbin.enable = true;
      calibre.web.enable = true;
      syncthing = {
        relay.enable = false;
        discovery.enable = false;
      };
      languagetool.enable = false;
      # mailserver = with secrets.mailserver; {
      #   enable = true;
      #   inherit fqdn sendingFqdn domains;
      #   loginAccounts =
      #     builtins.mapAttrs
      #       # deadnix: skip
      #       (name: value: {
      #         hashedPasswordFile = value.hashedPassword.secret.file;
      #         inherit (value) aliases;
      #         sendOnly = lib.mkIf (value ? sendOnly) value.sendOnly;
      #       })
      #       loginAccounts;
      # };
      miniflux = {
        enable = true;
        # adminCredsFile = secrets.miniflux.adminCredentials.secret.file;
      };
      taskserver = {
        enable = true;
        address = "10.55.0.2";
        fqdn = "chairlift.wg";
        firewall = "wg";
      };
      ankisyncd = {
        # build is broken
        enable = false;
        address = "10.55.0.2";
        firewall = "wg";
      };
      proxy = {
        enable = true;
        firewall = "wg";
        address = "10.55.0.2";
      };
      unbound = {
        enable = true;
        access = "wg";
        enableWGDomain = true;
      };
    }
  ];

  desktopConfig = utils.recursiveMerge [
    defaultClientConfig
    {
      boot.type = "uefi";
      kernel.initrdMods = [
        "nvme"
        "xhci_pci"
        "ahci"
        "usb_storage"
        "usbhid"
        "sd_mod"
      ];
      kernel.mods = [ "kvm-amd" ];
      fs = {
        type = "zfs-v2";
        hostId = "f5db52d8";
      };

      core.time = null;
      users.mutableUsers = false;

      desktop.enable = true;
      greetd.enable = true;
      # TODO: enable impermanence again
      impermanence.enable = false;
      # wireguard = wireguardConf;
      # waydroid.enable = true;
      # secrets.identityPaths = [ secrets.age.desktop.system.privateKeyPath ];
    }
  ];

  laptopConfig = utils.recursiveMerge [
    defaultClientConfig
    {
      boot.type = "uefi";
      fs.type = "encrypted-efi";
      laptop.enable = true;
      # secrets.identityPaths = [ "" ];
      networking.interfaces = [ "enp0s31f6" ];
      kernel.initrdMods = [
        "xhci_pci"
        "nvme"
        "usb_storage"
        "sd_mod"
        "rtsx_pci_sdmmc"
      ];
      kernel.mods = [ "kvm-intel" ];
    }
  ];

  hostData =
    name:
    builtins.fromJSON
      retired.nixosConfigurations.${name}.config.environment.etc."hmsystemdata.json".text;
  retired = {
    installMedia = {
      kde = host.mkISO {
        name = "kde-nixos";
        systemConfig = {
          sound = true;
        };
      };
      yubikey = host.mkISO {
        name = "yubikey-nixos";
        systemConfig = {
          airgap = true;
          yubikey = true;
        };
      };
    };

    nixosConfigurations = {
      laptop = host.mkHost {
        name = "laptop";
        systemConfig = laptopConfig;
        cpuCores = 4;
        stateVersion = "21.05";
      };

      desktop = host.mkHost {
        name = "desktop";
        systemConfig = desktopConfig;
        cpuCores = 12;
        stateVersion = "21.11";
      };

      chairlift = host.mkHost {
        name = "chairlift";
        systemConfig = chairliftConfig;
        cpuCores = 2;
        stateVersion = "21.11";
      };

      gondola = host.mkHost {
        name = "gondola";
        systemConfig = gondolaConfig;
        cpuCores = 8;
        stateVersion = "21.11";
      };
    };

    homeConfigurations = {
      "jd@desktop" = mkHome (hostData "desktop");
      "jd@laptop" = mkHome (hostData "laptop");
    };

    deploy.nodes.chairlift = {
      hostname = "10.55.0.2";
      sshOpts = [
        "-p"
        "23"
      ];
      autoRollback = true;
      magicRollback = true;
      profiles = {
        system = {
          sshUser = "root";
          user = "root";
          path = inputs.deploy-rs.lib.${system}.activate.nixos retired.nixosConfigurations.chairlift;
        };
      };
    };

    deploy.nodes.gondola = {
      hostname = "38.45.64.210";
      sshOpts = [
        "-p"
        "23"
      ];
      autoRollback = true;
      magicRollback = true;
      profiles = {
        system = {
          sshUser = "root";
          user = "root";
          path = inputs.deploy-rs.lib.${system}.activate.nixos retired.nixosConfigurations.gondola;
        };
      };
    };

  };
in
retired
