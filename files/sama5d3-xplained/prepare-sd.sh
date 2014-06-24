#!/bin/sh

set -e

[ -n "$1" ] || exit 1

DISK="$1"

sudo sfdisk --in-order --Linux --unit M ${DISK} <<-__EOF__
,64,0xE,*
;
__EOF__

sleep 3

PART1="${DISK}1"
PART2="${DISK}2"
if [ ! -b "${PART1}" ]
then
	PART1="${DISK}p1"
	PART2="${DISK}p2"
fi
if [ ! -b "${PART1}" ]
then
	echo Partitions do not exist
	exit 1
fi

sudo mkfs.vfat -F 16 "${PART1}" -n boot
# ext4 will default to huge file support, not part of default kernel (2tb). disable:
sudo tune2fs -O ^huge_file "${PART2}"
sudo mkfs.ext4 "${PART2}" -L rootfs
