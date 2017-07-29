#!/bin/sh
# http://www.rodsbooks.com/gdisk/sgdisk-walkthrough.html

set -e
source $(command -v envdefault || true) $DIR/env.export

[ -z "$1" ] && echo "Specify a disk" && exit 1 
dev=$1
[ -b "$dev" ] || echo "dev '$dev' not a device" && exit 1

echo initial gpt partition table setup
sgdisk -og $dev
echo

# find end of drive
ENDSECTOR=`sgdisk -E $dev`
echo

# build partitions

sgdisk -n $PARTITION_EFI:4096:200703 -c $PARTITION_EFI:"EFI System Partition" -t $PARTITION_EFI:ef00 $dev
echo
sgdisk -n $PARTITION_BIOS:2048:4095 -c $PARTITION_BIOS:"BIOS Boot Partition" -t $PARTITION_BIOS:ef02 $dev
echo
sgdisk -n $PARTITION_LINUX:200704:$ENDSECTOR -c $PARTITION_LINUX:$LABEL_LINUX -t $PARTITION_LINUX:8300 $dev
echo

# print

echo final state:
sgdisk -p $dev
echo

# tell linux about new partitions

partprobe $dev

# partition

mkfs.vfat $dev$PARTITION_EFI
#mkfs.btrfs ${1}1
mkfs.ext4 $dev$PARTITION_LINUX
