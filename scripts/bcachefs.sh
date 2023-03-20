DEVICE=$1
LABEL=$2
FS_LABEL=$3

if [ ! -n "$DEVICE" ] || [ ! -n "$LABEL" ] || [ ! -n "$FS_LABEL" ]; then
    echo "Need to set args"
    exit 1
fi


wipe() {
    sgdisk --zap-all $DEVICE
    # EFI partition
    sgdisk -n 0:0:+512MiB -t 0:ef00 -c 0:boot $DEVICE
    # 8200 is linux file system
    sgdisk -n 0:0:0 -t 0:8200 -c 0:swap $DEVICE

}


BOOT=${DEVICE}1
mkfs.vfat -n BOOT $BOOT

BCACHE=${DEVICE}2

format() {
    echo "Formatting bcachefs"
    bcachefs format \
        --discard \
        --label $LABEL \
        $BCACHE \
        --metadata_checksum=xxhash \
        --data_checksum=xxhash \
        --str_hash=siphash \
        --compression=zstd \
        --foreground_target=$LABEL \
        --acl \
        --usrquota \
        --grpquota \
        --prjquota \
        --encrypted  \
        --fs_label=$FS_LABEL
    echo "Unlock bcachefs"
    bcachefs unlock $BCACHE
}

mk_subvolume() {
    echo "Making subvolumes"
    # TODO: reservation subvolume?
    bcachefs subvolume create local
    bcachefs subvolume create local/root
    bcachefs subvolume create local/nix
    bcachefs subvolume create local/home

    bcachefs subvolume create persist/root
    bcachefs subvolume create persist/home
}

snapshot_blank() {
    echo "Snapshotting subvolumes"
    mkdir snapshots
    bcachefs snapshot $FS_LABEL/local/root $FS_LABEL/snapshots/root-blank
    bcachefs snapshot $FS_LABEL/local/home@blank $FS_LABEL/snapshots/home-blank
}

wipe
format

mount -t bcachefs $BCACHE /mnt
cd mnt

# Online actions
mk_subvolume
snapshot_blank
