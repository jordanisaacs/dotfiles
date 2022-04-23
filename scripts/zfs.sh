# TODO: change to script arguments

sgdisk --zap-all /dev/sda

SDA_ID="$(ls /dev/disk/by-id/ | grep '^[scsi]')"
DISK=/dev/disk/by-id/$SDA_ID

sgdisk -n 0:0:+1MiB -t 0:ef02 -c 0:grub $DISK
sgdisk -n 0:0:+512MiB -t 0:ea00 -c 0:boot $DISK
sgdisk -n 0:0:+2GiB -t 0:8200 -c 0:swap $DISK
sgdisk -n 0:0:0 -t 0:BF01 -c 0:ZFS $DISK

BOOT=$DISK-part2
SWAP = $DISK-part3
ZFS=$DISK-part4

mkswap -L SWAP $SWAP
mkfs.vfat -n BOOT $BOOT

zpool create \
  -o ashift=12 \
  -o autotrim=on \
  -R /mnt \
  -O canmount=off \
  -O mountpoint=none \
  -O acltype=posixacl \
  -O compression=zstd \
  -O dnodesize=auto \
  -O normalization=formD \
  -O relatime=on \
  -O xattr=sa \
  -O encryption=aes-256-gcm \
  -O keylocation=prompt \
  -O keyformat=passphrase \
  rpool \
  $ZFS

# Reserve 1GB to allow ZFS operations
zfs create -o refreservation=1G -o mountpoint=none rpool/reserved

zfs create -p -o canmount=on -o mountpoint=legacy rpool/local/root
zfs create -p -o canmount=on -o mountpoint=legacy rpool/local/nix
zfs create -p -o canmount=on -o mountpoint=legacy rpool/local/home

zfs create -p -o canmount=on -o mountpoint=legacy rpool/persist/root
zfs create -p -o canmount=on -o mountpoint=legacy rpool/persist/home

zfs snapshot rpool/local/root@blank
zfs snapshot rpool/local/home@blank

mount -t zfs rpool/local/root /mnt

mkdir /mnt/boot
mount $BOOT /mnt/boot

mkdir /mnt/nix
mount -t zfs rpool/local/nix /mnt/nix

mkdir /mnt/home
mount -t zfs rpool/local/home /mnt/home

mkdir /mnt/persist
mount -t zfs rpool/persist/root /mnt/persist

mkdir /mnt/persist/home
mount -t zfs rpool/persist/home /mnt/persist/home
