#!/bin/sh

set -e

[ -n "$1" ] || exit 1

DISK="$1"

#sudo dd if=/dev/zero of=${DISK} bs=1M count=16

sudo sfdisk --in-order --Linux --unit M ${DISK} <<-__EOF__
,64,0xE,*
;
__EOF__

sleep 4

PART1="${DISK}1"
PART2="${DISK}2"
if [ ! -b "${PART1}" ]
then
	PART1="${DISK}p1"
	PART2="${DISK}p2"
fi

sudo mkfs.vfat -F 16 ${PART1} -n boot
sudo mkfs.ext4 ${PART2} -L rootfs
