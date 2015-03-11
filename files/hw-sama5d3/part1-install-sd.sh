#!/bin/sh

set -e

[ -n "$2" ] && VAR="$2"
[ -z "$VAR" ] && VAR="{{VAR}}"
[ -z "$BOOT_MNT" ] && [ -b "$1 " ] && BOOT_MNT=`mktemp -d --suffix=boot-mnt --tmpdir=.` && sudo mount "$1" "${BOOT_MNT}"

# copy boot files on to sd card
sudo cp ${VAR}/u-boot-spl-sd.bin "${BOOT_MNT}/BOOT.BIN"
sudo cp ${VAR}/u-boot-sd.img "${BOOT_MNT}/u-boot.img"
sudo cp ${VAR}/uEnv.txt "${BOOT_MNT}/"
sudo cp ${VAR}/vmlinuz-latest "${BOOT_MNT}/zImage"
sudo cp ${VAR}/at91-sama5d3_xplained.dtb "${BOOT_MNT}/"
sudo umount "${BOOT_MNT}"
rm -rf "${BOOT_MNT}"
