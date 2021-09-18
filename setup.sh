DISK=$1
RAM=$2

sgdisk --zap-all "$DISK"
sgdisk -n1:2048:+550MiB             -t1:ef00    -c1:"EFI system partition"      "$DISK"
# Size of luks header is 16MiB. So 4MiB keyfile
sgdisk -n2:0:+17MiB                 -t2:8300    -c2:"cryptsetup luks key"       "$DISK"
sgdisk -n3:0:+${RAM}GiB             -t3:8300    -c3:"swap space (hibernation)"  "$DISK"
sgdisk -n4:0:"$(sgdisk -E "$DISK")" -t4:8300    -c4:"root filesystem"           "$DISK"

cryptsetup luksFormat   "${DISK}p2" --type luks2   
cryptsetup config       "${DISK}p3" --label NIXKEY
cryptsetup luksOpen     "${DISK}p2" cryptkey
dd if=/dev/urandom of=/dev/mapper/cryptkey


cryptsetup luksFormat   "${DISK}p3" --key-file=/dev/mapper/cryptkey --type luks2
cryptsetup config       "${DISK}p3" --label NIXSWAP
cryptsetup luksOpen     "${DISK}p3" --key-file=/dev/mapper/cryptkey cryptswap
mkswap -L DECRYPTNIXSWAP /dev/mapper/cryptswap
swapon /dev/disk/by-label/DECRYPTNIXSWAP

cryptsetup luksFormat   "${DISK}p4" --type luks2
cryptsetup config       "${DISK}p4" --label NIXROOT
cryptsetup luksAddKey   "${DISK}p4" /dev/mapper/cryptkey
cryptsetup luksOpen     "${DISK}p4" --key-file=/dev/mapper/cryptkey cryptroot
mkfs.ext4 -L DECRYPTNIXROOT /dev/mapper/cryptroot
mount /dev/disk/by-label/DECRYPTNIXROOT /mnt

mkfs.vfat -n BOOT "${DISK}p1"
mkdir /mnt/boot
mount /dev/disk/by-label/BOOT /mnt/boot

nixos-generate-config --root /mnt



