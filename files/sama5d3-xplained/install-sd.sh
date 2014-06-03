#!/bin/sh

set -e

if [ -n "$1" ]
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

BOOTMNT=`mktemp -d --suffix=boot-mnt --tmpdir=.`
sudo mount "${PART1}" "${BOOTMNT}"
sudo cp bin/u-boot-sd.spl "${BOOTMNT}/BOOT.BIN"
sudo cp bin/u-boot-sd.img "${BOOTMNT}/u-boot.img"
sudo cp uEnv.txt "${BOOTMNT}/"
sudo cp linux.dtb "${BOOTMNT}/"
sudo umount "${BOOTMNT}"
rm -rf "${BOOTMNT}"

ROOTMNT=`mktemp -d --suffix=root-mnt --tmpdir=.`
sudo mount "${PART2}" "${ROOTMNT}"
sudo umount "${ROOTMNT}"
rm -rf "${ROOTMNT}"
