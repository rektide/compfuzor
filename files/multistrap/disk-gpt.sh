#!/bin/sh

# http://www.rodsbooks.com/gdisk/sgdisk-walkthrough.html

set -e
set -x

[ -z "$1" ] && echo "Specify a disk" && exit

echo gpt partition table setup
sgdisk -og $1
sgdisk -n 1:2048:4095 -c 1:"BIOS Boot Partition" -t 1:ef02 $1
sgdisk -n 2:4096:200703 -c 2:"EFI System Partition" -t 2:ef00 $1
ENDSECTOR=`sgdisk -E $1`
sgdisk -n 3:20074:$ENDSECTOR -c 3:"Linux" -t 3:8300 $1
sgdisk -p $1

echo mkfs
mkfs.vfat ${1}2
mkfs.btrfs ${1}3

#TMP=`mktemp --suffix=.pdebuildx.part -d --tmpdir=.`
#mount ${1}2 $TMP
#mkdir $TMP/.syslinux
#umount $TMP
#rm -rf $TMP
#syslinux -i -d '.syslinux' ${1}1
