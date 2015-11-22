#!/bin/sh

set -e

. $(dirname $(readlink -f $0))/mnt.env
. $(dirname $(readlink -f $0))/var.env

# copy boot files on to sd card
sudo cp ${VAR}/u-boot-spl-sd.bin "${MNT}/BOOT.BIN"
sudo cp ${VAR}/u-boot-sd.img "${MNT}/u-boot.img"
sudo cp ${VAR}/uEnv.txt "${MNT}/"
sudo cp ${VAR}/vmlinuz-latest "${MNT}/zImage"
sudo cp ${VAR}/at91-sama5d3_xplained.dtb "${MNT}/"

[ "$HAD_MNT" = "false" ] && sudo umount "${MNT}" && rm -rf "${MNT}"
