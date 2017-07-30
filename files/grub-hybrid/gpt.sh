#!/bin/bash
# http://www.rodsbooks.com/gdisk/sgdisk-walkthrough.html

set -e
[ -z "$1" ] && echo "Specify a disk" && exit 1 
DEV=$1
[ ! -b "$DEV" ] && echo "dev '$DEV' not a device" >&2 && exit 1
[ -n "$ENV_BYPASS" ] || source $(command -v envdefault || true) {{DIR}}/env.export >/dev/null

echo initial gpt partition table setup
sgdisk -og $DEV

# find end of drive
ENDSECTOR=`sgdisk -E $DEV`

# build partitions

partnum_efi=${PARTITION_EFI:${#PARTITION_EFI}-1:1}
sgdisk -n $partnum_efi:4096:200703 -c $partnum_efi:"EFI System Partition" -t $partnum_efi:ef00 $DEV
partnum_bios=${PARTITION_BIOS:${#PARTITION_BIOS}-1:1}
sgdisk -n $partnum_bios:2048:4095 -c $partnum_bios:"BIOS Boot Partition" -t $partnum_bios:ef02 $DEV
partnum_linux=${PARTITION_LINUX:${#PARTITION_LINUX}-1:1}
sgdisk -n $partnum_linux:200704:$ENDSECTOR -c $partnum_linux:"$LABEL_LINUX" -t $partnum_linux:8300 $DEV

# print

echo final state:
sgdisk -p $DEV
echo

# tell linux about new partitions

partprobe $DEV
sleep 1

# partition

mkfs.vfat $PARTITION_EFI
#mkfs.btrfs ${1}1
mkfs.ext4 $PARTITION_LINUX
