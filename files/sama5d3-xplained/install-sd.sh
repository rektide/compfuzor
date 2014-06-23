#!/bin/sh

set -e

test -z "$2" && export VAR="{{VAR}}"
test -z "$3" && export IMAGE="${VAR}/pdebuild-cross.tgz"

if [ -z "$1" ]
then
	echo "no target specified"
	exit 1
fi
DISK="$1"

PART1="${DISK}1"
PART2="${DISK}2"
if [ ! -b "${PART1}" ]
then
	PART1="${DISK}p1"
	PART2="${DISK}p2"
fi

if [ ! -b "${PART1}" ]
then
	echo "partition not found"
	exit 2
fi

# copy boot files on to sd card
BOOT_MNT=`mktemp -d --suffix=boot-mnt --tmpdir=.`
sudo mount "${PART1}" "${BOOT_MNT}"
sudo cp ${VAR}/u-boot-sd.spl "${BOOT_MNT}/BOOT.BIN"
sudo cp ${VAR}var/u-boot-sd.img "${BOOT_MNT}/u-boot.img"
sudo cp ${VAR}/uEnv.txt "${BOOT_MNT}/"
sudo cp ${VAR}/vmlinuz-latest "${BOOT_MNT}/zImage"
sudo cp ${VAR}/at91-sama5d3_xplained.dtb "${BOOT_MNT}/"
sudo umount "${BOOT_MNT}"

# copy configured image on to sd card
ROOT_MOUNT=`mktemp -d --suffix=root-mnt --tmpdir=.`
OLDD=`pwd`
sudo mount "${PART2}" "${ROOT_MNT}"
cd "${ROOT_MOUNT}"
tar -xzf "${VAR}/${IMAGE}"
cd "${OLDD}"
sudo umount "${ROOT_MNT}"
rm -rf "${ROOT_MNT}"
