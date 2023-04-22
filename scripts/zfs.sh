set -e

DISK=$1

sgdisk --zap-all $DISK

sgdisk -n 0:0:+512MiB -t 0:ef00 -c 0:boot $DISK
sgdisk -n 0:0:0 -t 0:8200 -c 0:zfs $DISK


printf 'Disk is nvme (y/n)? '
old_stty_cfg=$(stty -g)
stty raw -echo
answer=$(while ! head -c 1 | grep -i '[ny]' ;do true ;done )
stty $old_stty_cfg
if [ "answer" != "${answer#[Yy]}" ]; then
  BOOT=${DISK}p1
  ZFS=${DISK}p2
else
  BOOT=${DISK}1
  ZFS=${DISK}2
fi

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

# Base mount
zfs create -p -o canmount=on -o mountpoint=legacy rpool/local
zfs snapshot rpool/local@blank

# Home mount
zfs create -p -o canmount=on -o mountpoint=legacy rpool/local/home
zfs snapshot rpool/local/home@blank

# Nix store mounts
zfs create -p -o canmount=on -o mountpoint=legacy rpool/persist/nix

# Root mounts (erased every boot)
zfs create -p -o canmount=on -o mountpoint=legacy rpool/local/root
zfs create -p -o canmount=on -o mountpoint=legacy rpool/backup/root
zfs create -p -o canmount=on -o mountpoint=legacy rpool/persist/root

zfs snapshot rpool/local/root@blank

# Data pool, part of service being backed up
zfs create -p -o canmount=on -o mountpoint=legacy rpool/persist/data
zfs create -p -o canmount=on -o mountpoint=legacy rpool/backup/data


install_jd() {
  zfs create -p -o canmount=on -o mountpoint=legacy rpool/local/home/jd
  zfs create -p -o canmount=on -o mountpoint=legacy rpool/persist/home/jd
  zfs create -p -o canmount=on -o mountpoint=legacy rpool/backup/home/jd

  zfs snapshot rpool/local/home/jd@blank
}

printf 'Make jd pool (y/n)? '
old_stty_cfg=$(stty -g)
stty raw -echo
answer=$(while ! head -c 1 | grep -i '[ny]' ;do true ;done )
stty $old_stty_cfg
if [ "answer" != "${answer#[Yy]}" ]; then
  install_jd
fi

mount -t zfs rpool/local /mnt

mkdir /mnt/boot
mount $BOOT /mnt/boot

mkdir /mnt/home
mount -t zfs rpool/local/home /mnt/home

mkdir /mnt/root
mount -t zfs rpool/local/root /mnt/root

mkdir /mnt/nix
mount -t zfs rpool/persist/nix /mnt/nix

mkdir -p /mnt/persist/root
mount -t zfs rpool/persist/root /mnt/persist/root

mkdir -p /mnt/persist/data
mount -t zfs rpool/persist/data /mnt/persist/data

mkdir -p /mnt/backup/root
mount -t zfs rpool/backup/root /mnt/backup/root

mkdir -p /mnt/backup/data
mount -t zfs rpool/backup/data /mnt/backup/data
