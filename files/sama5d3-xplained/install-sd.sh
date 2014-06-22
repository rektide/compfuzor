#!/bin/sh

IMAGE="pdebuild-cross.tgz"

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

# copy boot files on to sd card
BOOT_MNT=`mktemp -d --suffix=boot-mnt --tmpdir=.`
sudo mount "${PART1}" "${BOOT_MNT}"
sudo cp lib/u-boot-sd.spl "${BOOT_MNT}/BOOT.BIN"
sudo cp lib/u-boot-sd.img "${BOOT_MNT}/u-boot.img"
sudo bin/extract-from-tar.sh vmlinuz
sudo cp uEnv.txt "${BOOT_MNT}/"
sudo cp linux.dtb "${BOOT_MNT}/"
sudo umount "${BOOT_MNT}"
rm -rf "${BOOT_MNT}"

# extract image to a temporary folder and configure
INSTALL_MOUNT=`mktemp -d --suffix=install-mnt --tmpdir=.`
OLDD=`pwd`
cd "${INSTALL_MOUNT}"
tar -xzf "${IMAGE}"
sudo cp ../linux.dtb 
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

# copy configured image on to sd card
ROOT_MOUNT=`mktemp -d --suffix=root-mnt --tmpdir=.`
sudo mount "${PART2}" "${ROOT_MNT}"
sudo cp -aur "${INSTALL_MNT}" "${ROOT_MNT}/"

# unmount
sudo umount "${ROOT_MNT}"
rm -rf "${ROOT_MNT}"
sudo umount "${INSTALL_MOUNT}"
rm -rf "${INSTALL_MOUNT}"
