#!/bin/sh

[ -n "$1" ] || echo "Specify a disk" && exit

echo {{ETC}}/basic.parted | parted $1
mkfs.vfat ${1}1
mkfs.btrfs ${1}2
TMP=`mktemp --suffix=.pdebuildx.part -d --tmpdir=.`
mount ${1}1 $TMP
mkdir $TMP/.syslinux
umount $TMP
rm -rf $TMP
syslinux -i -d '.syslinux' ${1}1
