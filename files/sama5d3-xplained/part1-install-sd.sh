#!/bin/sh

set -e

if [ ! -b "$1" ]
then
	echo Not a block device to instal boot files into
	exit 2
fi

if [ -z "${VAR}" ]
then
	if [ -n "$2" ]
	then
		VAR="$2"
	else
		VAR="{{VAR}}"
	fi
fi

# copy boot files on to sd card
BOOT_MNT=`mktemp -d --suffix=boot-mnt --tmpdir=.`
sudo mount "${1}" "${BOOT_MNT}"
sudo cp ${VAR}/u-boot-sd.spl "${BOOT_MNT}/BOOT.BIN"
sudo cp ${VAR}/u-boot-sd.img "${BOOT_MNT}/u-boot.img"
sudo cp ${VAR}/uEnv.txt "${BOOT_MNT}/"
sudo cp ${VAR}/vmlinuz-latest "${BOOT_MNT}/zImage"
sudo cp ${VAR}/at91-sama5d3_xplained.dtb "${BOOT_MNT}/"
sudo umount "${BOOT_MNT}"
rm -rf "${BOOT_MNT}"
