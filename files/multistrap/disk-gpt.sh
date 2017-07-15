#!/bin/sh
# http://www.rodsbooks.com/gdisk/sgdisk-walkthrough.html

set -e

[ -z "$1" ] && echo "Specify a disk" && exit

echo gpt partition table setup
sgdisk -og $1
echo
ENDSECTOR=`sgdisk -E $1`
sgdisk -n 1:200704:$ENDSECTOR -c 1:"Linux" -t 1:8300 $1
echo
sgdisk -n 2:4096:200703 -c 2:"EFI System Partition" -t 2:ef00 $1
echo
sgdisk -n 3:2048:4095 -c 3:"BIOS Boot Partition" -t 3:ef02 $1
sgdisk -p $1

partprobe /dev/sde

mkfs.vfat ${1}2
mkfs.btrfs ${1}1
