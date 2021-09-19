{ pkgs, lib }:
let
  setupTools = with pkgs; writeScriptBin "setup" ''
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

  # following script from:
  # https://github.com/wiltaylor/dotfiles/blob/master/roles/core/scripts.nix
  sysTools = with pkgs; writeScriptBin "sys" ''
    #!${runtimeShell}
    if [ -n "$INNIXSHELLHOME" ]; then
      echo "You are in a nix shell that redirected home!"
      echo "SYS will not work from here properly."
      exit 1
    fi

    case $1 in
      "clean")
        echo "Running garbage collection"
        nix-store --gc
        echo "Deduplication running... may take a while"
        nix-store --optimise
      ;;

      "update")
        echo "Updating nixos flake..."
        pushd ~/.dotfiles
        nix flake update
        popd
      ;;

      "update-index")
        echo "Updating index... may take a while"
        nix-index
      ;;

      "save")
        echo "Saving changes"
        pushd ~/.dotfiles
        git diff
        git add .
        git commit
        git pull --rebase
        git push
      ;;

      "search")
        if [ $2 = "--overlay" ]; then
          pushd ~/.dotfiles
          nix search .# $3
          popd
        else
          nix search nixpkgs $2
        fi
      ;;

      "find-doc")
        ${manix}/bin/manix $2
      ;;

      "find-cmd")
        nix-locate --whole-name --type x --type s --no-group --type x --type s --top-level --at-root "/bin/$2"
      ;;

      "apply")
        pushd ~/.dotfiles
        if [ -z "$2" ]; then
          sudo nixos-rebuild switch --flake '.#'
        elif [ $2 = "--boot" ]; then
          sudo nixos-rebuild boot --flake '.#'
        elif [ $2 = "--test" ]; then
          sudo nixos-rebuild test --flake '.#'
        elif [ $2 = "--check" ]; then
          nixos-rebuild dry-activate --flake '.#'
        else
          echo "Unknown option $2"
        fi
        popd
      ;;

      "apply-user")
        pushd ~/.dotfiles

        #--impure is required so package can reach out to /etc/hmsystemdata.json
        nix build --impure .#homeManagerConfigurations.$USER.activationPackage
        ./result/activate
        popd
      ;;

      "iso")
        echo "Building iso file $2"
        pushd ~/.dotfiles
        nix build ".#installMedia.$2.config.system.build.isoImage"

        if [ -z "$3" ]; then
          echo "ISO Image is located at ~/.dotfiles/result/iso/nixos.iso"
        elif [ $3 = "--burn" ]; then
          if [ -z "$4" ]; then
            echo "Expected path to a usb drive following --burn"
          else
            sudo dd if=./result/iso/nixos.iso of=$4 status=progress bs=1M
          fi
        else
          echo "Unexpected option $3. Expected --burn"
        fi
        popd
      ;;

      "installed")
        nix-store -qR /run/current-system | sed -n -e 's/\/nix\/store\/[0-9a-z]\{32\}-//p' | sort | uniq
      ;;

      "depends")
        nix-store -qR $(which $2)
      ;;

      "exec")
        shift 1
        cmd=$1
        pkgs=$(nix-locate --minimal --no-group --type x --type s --top-level --whole-name --at-root "/bin/$cmd")
        count=$(echo -n "$pkgs" | grep -c "^")

        case $count in
          0)
            >&2 echo "$1: not found!"
            exit 2
          ;;

          1)
            nix-build --no-out-link -A $pkgs "<nixpkgs>"
            if [ "$?" -eq 0 ]; then
              nix-shell -p $pkgs --run "$(echo $@)"
              exit $?
            fi
          ;;

          *)
            PS3="Please select package to run command from:"
            select p in $pkgs
            do
              nix-build --no-out-link -A $p "<nixpkgs>"
              if [ "$?" -eq 0 ]; then
                nix-shell -p $pkgs --run "$(echo $@)"
                exit $?
              fi

              >&2 echo "Unable to run command"
              exit $?
            done
          ;;
        esac
      ;;

      *)
        echo "Usage:"
        echo "sys command"
        echo ""
        echo "Commands:"
        echo "clean - Garbage collect and hard link nix store"
        echo "update - Updates dotfiles flake."
        echo "update-index - Updates index of nix Used for exec"
        echo "find [--overlay] - Find a nix package (overlay for custom packages)"
        echo "find-doc - Finds documentation on a config item"
        echo "find-cmd - Finds the package a command is in"
        echo "apply - Applies current system configuration in dotfiles."
        echo "apply-user - Applies current home manager configuration in dotfiles."
        echo "shell - Runs a shell defined in flake."
        echo "installed - Lists all installed packages."
        echo "which - Prints the closure of target file"
        echo "exec - executes a command"
      ;;
    esac
  '';
  bluetoothTools = with pkgs; writeScriptBin "btools" ''
    #!${runtimeShell}

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
  soundTools = with pkgs; writeScriptBin "stools" ''
    #!${runtimeShell}
    
    num_param () {
      re='^[0-9]+$'

      if [[ -z $1 ]]; then
        if [[ -z $2 ]]; then
          echo "Missing number parameter."
          exit 1
        elif [[ $2 =~ $re ]]; then
          echo $2
        else
          echo "Invalid parameter, expects a number: $2"
          exit 1
        fi
      elif [[ $1 =~ $re ]]; then
        echo $1
      else
        echo "Invalid parameter, expects a number: $1"
        exit 1
      fi
    }

    case $1 in
      "vol")
        case $2 in
          "get")
            sink=$(${pulseaudio}/bin/pactl info | ${gawk}/bin/awk -F': ' '/Default Sink/{print $2}')
            ${pulseaudio}/bin/pactl list sinks | ${gawk}/bin/awk "\$1 ~ /Volume/ && \$5 ~ /[0-9]+/{if(found_sink){ print \$5; found_sink=0}}; /Name: $sink/{found_sink=1}"
          ;;
          
          "up")
            sink=$(${pulseaudio}/bin/pactl info | ${gawk}/bin/awk -F': ' '/Default Sink/{print $2}')
            curr_vol=$(${pulseaudio}/bin/pactl list sinks | ${gawk}/bin/awk "\$1 ~ /Volume/ && \$5 ~ /[0-9]+/{if(found_sink){ print (\$5+0); found_sink=0}}; /Name: $sink/{found_sink=1}")

            delta=$(num_param $3 2)
            if [ $? = 1 ]; then
              echo $delta
              exit 1
            fi

            max_vol=$(num_param $4 150)
            if [ $? = 1 ]; then
              echo $max_vol
              exit 1
            fi

            new_vol=$((curr_vol+delta))
            ${pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ $((new_vol>max_vol ? max_vol : new_vol))%
          ;;

          "down")
            sink=$(${pulseaudio}/bin/pactl info | ${gawk}/bin/awk -F': ' '/Default Sink/{print $2}')
            curr_vol=$(${pulseaudio}/bin/pactl list sinks | ${gawk}/bin/awk "\$1 ~ /Volume/ && \$5 ~ /[0-9]+/{if(found_sink){ print (\$5+0); found_sink=0}}; /Name: $sink/{found_sink=1}")

            delta=$(num_param $3 2)
            if [ $? = 1 ]; then
              echo $vol
              exit 1
            fi

            new_vol=$((curr_vol-delta))
            ${pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ $((new_vol<0 ? 0 : new_vol))%
          ;;

          "set")
            vol=$(num_param $3)
            if [ $? = 1 ]; then
              echo $vol
              exit 1
            fi

            ${pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ ''${vol}%
          ;;

          "toggle")
            ${pulseaudio}/bin/pactl set-sink-mute @DEFAULT_SINK@ toggle
          ;;

          *)
            echo "Usage"
            echo "stools vol command"
            echo ""
            echo "Commands:"
            echo "get: Get current default sink volume"
            echo "up: Raise the % default sink volume. \$1=2 is vol delta, \$2=150 is max vol"
            echo "down: Lower the % default sink volume. \$1=2 is vol delta"
            echo "set \$1: Set the % default sink volume to \$1."
            echo "toggle: Mute/unmute default sink volume"
          ;;
        esac
      ;;

      "mic")
        case $2 in
          "toggle")
            ${pulseaudio}/bin/pactl set-source-mute @DEFAULT_SOURCE@ toggle
          ;;

          *)
            echo "Usage"
            echo "stools mic command"
            echo ""
            echo "Commands:"
            echo "toggle: Mute/unmute default source mic"
          ;;
        esac
      ;;

      *)
        echo "Sound Tools Usage"
        echo "stools command"
        echo ""
        echo "Commands:"
        echo "vol: actions related to volume"
      ;;
    esac
  '';
in {
  overlay = (final: prev: {
    scripts.sysTools = sysTools;
    scripts.bluetoothTools = bluetoothTools;
    scripts.soundTools = soundTools;
    scripts.setupTools = setupTools;
  });
}

