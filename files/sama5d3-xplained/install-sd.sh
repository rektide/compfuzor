#!/bin/sh

IMAGE="{{DIR}}/pdebuild-cross.tgz"

set -e

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

BOOTMNT=`mktemp -d --suffix=boot-mnt --tmpdir=.`
sudo mount "${PART1}" "${BOOTMNT}"
sudo cp bin/u-boot-sd.spl "${BOOTMNT}/BOOT.BIN"
sudo cp bin/u-boot-sd.img "${BOOTMNT}/u-boot.img"
sudo cp uEnv.txt "${BOOTMNT}/"
sudo cp linux.dtb "${BOOTMNT}/"
sudo umount "${BOOTMNT}"
rm -rf "${BOOTMNT}"

ROOTMNT=`mktemp -d --suffix=root-mnt --tmpdir=.`
OLDD=`pwd`
sudo mount "${PART2}" "${ROOTMNT}"
cd "${ROOTMNT}"
tar -xzf "${IMAGE}"
sudo cp /usr/bin/qemu-arm-static usr/bin
sudo mount --bind /proc proc
sudo mount --bind /dev dev
sudo chroot . /bin/dash -x <<'EOF'
export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true
export LC_ALL=C LANGUAGE=C LANG=C
debconf-set-selections <<TZSEL
tzdata tzdata/Areas select US
tzdata tzdata/Areas seen true
tzdata tzdata/Zones/US select Eastern
tzdata tzdata/Zones/US seen true
TZSEL
/var/lib/dpkg/info/dash.preinst install
dpkg --configure -a
ln -s /proc/self/mounts /etc/mtab
echo 'root:CHANGENOW' | chpasswd
EOF
sudo umount proc
sudo umount dev
sudo rm usr/bin/qemu-arm-static
cd "${OLDD}"
sudo umount "${ROOTMNT}"
rm -rf "${ROOTMNT}"
