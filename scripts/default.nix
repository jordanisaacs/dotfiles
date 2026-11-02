{
  pkgs,
  ...
}:
let
  setupTools =
    with pkgs;
    writeShellScriptBin "setup" ''
      DISK=$1
      RAM=$2

      sgdisk --zap-all "$DISK"
      sgdisk -n1:2048:+550MiB             -t1:ef00    -c1:"EFI system partition"      "$DISK"
      # Size of luks header is 16MiB. So 1MiB keyfile
      sgdisk -n2:0:+17MiB                 -t2:8300    -c2:"cryptsetup luks key"       "$DISK"
      sgdisk -n3:0:+''${RAM}GiB             -t3:8300    -c3:"swap space (hibernation)"  "$DISK"
      sgdisk -n4:0:"$(sgdisk -E "$DISK")" -t4:8300    -c4:"root filesystem"           "$DISK"

      cryptsetup luksFormat   "''${DISK}p2" --type luks2
      cryptsetup config       "''${DISK}p3" --label NIXKEY
      cryptsetup luksOpen     "''${DISK}p2" cryptkey
      dd if=/dev/urandom of=/dev/mapper/cryptkey


      cryptsetup luksFormat   "''${DISK}p3" --key-file=/dev/mapper/cryptkey --type luks2
      cryptsetup config       "''${DISK}p3" --label NIXSWAP
      cryptsetup luksOpen     "''${DISK}p3" --key-file=/dev/mapper/cryptkey cryptswap
      mkswap -L DECRYPTNIXSWAP /dev/mapper/cryptswap
      swapon /dev/disk/by-label/DECRYPTNIXSWAP

      cryptsetup luksFormat   "''${DISK}p4" --type luks2
      cryptsetup config       "''${DISK}p4" --label NIXROOT
      cryptsetup luksAddKey   "''${DISK}p4" /dev/mapper/cryptkey
      cryptsetup luksOpen     "''${DISK}p4" --key-file=/dev/mapper/cryptkey cryptroot
      mkfs.ext4 -L DECRYPTNIXROOT /dev/mapper/cryptroot
      mkdir /mnt
      mount /dev/disk/by-label/DECRYPTNIXROOT /mnt

      mkfs.vfat -n BOOT "''${DISK}p1"
      mkdir /mnt/boot
      mount /dev/disk/by-label/BOOT /mnt/boot

      nixos-generate-config --root /mnt
    '';

  pythonScript = import ../lib/python-script.nix { inherit pkgs; };
  sysTools = pythonScript "sys" ./sys.py {
    nix = "${pkgs.nixVersions.latest}/bin/nix";
    nixStore = "${pkgs.nixVersions.latest}/bin/nix-store";
    homeManager = "${pkgs.home-manager}/bin/home-manager";
    nixosRebuild = "${pkgs.nixos-rebuild}/bin/nixos-rebuild";
    manix = "${pkgs.manix}/bin/manix";
  };
  bluetoothTools =
    with pkgs;
    writeShellScriptBin "btools" ''
      case $1 in
        "connected")
           ${bluez}/bin/bluetoothctl devices | \
             cut -f2 -d' ' | \
             while read uuid; do ${bluez}/bin/bluetoothctl info $uuid; done | \
             ${gawk}/bin/awk -vid=8 -vname=7 '/Connected: yes/{print r[NR%id]; print l[NR%name]};{l[NR%name]=$0; r[NR%id]=$0}'
        ;;

        *)
          echo "Bluetooth Tools Usage:"
          echo "btools command"
          echo ""
          echo "Commands:"
          echo "connected: List connected devices"
        ;;
      esac
    '';
  soundTools = pythonScript "stools" ./sound.py {
    pactl = "${pkgs.pulseaudio}/bin/pactl";
  };

  devTools =
    with pkgs;
    writeShellScriptBin "dtools" ''
      case $1 in
        "hubclone")
          if [ -z "$2" ]; then
            echo "Need to set a github user to clone"
          elif [ -z "$3" ]; then
            echo "Need to set a repo name to clone"
          else
            cd ~/Documents/dev/
            "${git}/bin/git" clone https://github.com/$2/$3.git
          fi
        ;;

        *)
          echo "Dev Tools Usage"
          echo "dtools command"
          echo ""
          echo "Commands:"
          echo "hubclone \$1 \$2: Clone github repo (\$2) from user (\$1) in dev folder"
      esac
    '';
in
{
  overlay = _final: _prev: {
    jdScripts = {
      inherit
        sysTools
        bluetoothTools
        soundTools
        setupTools
        devTools
        ;
    };
  };
}
