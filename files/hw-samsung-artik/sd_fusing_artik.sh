#!/bin/bash

FORMAT=""
DEVICE=""
KERNEL=""
MODULES=""
PLATFORM=""

function fuse_image {
	if [ "$MODULES" != "" ]; then
		echo " == Fusing modules: $MODULES =="
		dd if=$MODULES of=$DEVICE"6"
	fi

	if [ "$PLATFORM" != "" ]; then
		echo " == Fusing platform: $PLATFORM =="
		TEMP_DIR="artik_platform_tmp"
		mkdir -p $TEMP_DIR
		cd $TEMP_DIR
		tar xvf $PLATFORM
		echo " == Fusing rootfs.img =="
		dd if=rootfs.img of=$DEVICE"2"
		echo " == Fusing system-data.img =="
		dd if=system-data.img of=$DEVICE"3"
		echo " == Fusing user.img =="
		dd if=user.img of=$DEVICE"5"
		cd ..
		rm -rf $TEMP_DIR
		eval sync
	fi

	if [ "$KERNEL" != "" ]; then
		echo " == Fusing kernel: $KERNEL =="
		TEMP_DIR="artik_kernel_tmp"
		mkdir -p $TEMP_DIR
		mount $DEVICE"1" $TEMP_DIR
		cp $KERNEL $TEMP_DIR/zImage
		eval sync
		umount $DEVICE"1"
		rm -rf $TEMP_DIR
	fi
}

function mkpart_3 {
	DISK=$DEVICE
	SIZE=`sfdisk -s $DISK`
	SIZE_MB=$((SIZE >> 10))

	BOOT_SZ=64
	ROOTFS_SZ=3072
	DATA_SZ=512
	MODULE_SZ=20

	let "USER_SZ = $SIZE_MB - $BOOT_SZ - $ROOTFS_SZ - $DATA_SZ - $MODULE_SZ - 4"

	BOOT=boot
	ROOTFS=rootfs
	SYSTEMDATA=system-data
	USER=user
	MODULE=modules

	if [[ $USER_SZ -le 100 ]]
	then
		echo "We recommend to use more than 4GB disk"
		exit 0
	fi

	echo "========================================"
	echo "Label          dev           size"
	echo "========================================"
	echo $BOOT"		" $DISK"1  	" $BOOT_SZ "MB"
	echo $ROOTFS"		" $DISK"2  	" $ROOTFS_SZ "MB"
	echo $SYSTEMDATA"	" $DISK"3  	" $DATA_SZ "MB"
	echo "[Extend]""	" $DISK"4"
	echo " "$USER"		" $DISK"5  	" $USER_SZ "MB"
	echo " "$MODULE"		" $DISK"6  	" $MODULE_SZ "MB"

	MOUNT_LIST=`mount | grep $DISK | awk '{print $1}'`
	for mnt in $MOUNT_LIST
	do
		umount $mnt
	done

	echo "Remove partition table..."                                                
	dd if=/dev/zero of=$DISK bs=512 count=1 conv=notrunc

	sfdisk --in-order --Linux --unit M $DISK <<-__EOF__
	4,$BOOT_SZ,0xE,*
	,$ROOTFS_SZ,,-
	,$DATA_SZ,,-
	,,E,-
	,$USER_SZ,,-
	,$MODULE_SZ,,-
	__EOF__

	mkfs.vfat -F 16 ${DISK}1 -n $BOOT
	mkfs.ext4 -q ${DISK}2 -L $ROOTFS -F
	mkfs.ext4 -q ${DISK}3 -L $SYSTEMDATA -F
	mkfs.ext4 -q ${DISK}5 -L $USER -F
	mkfs.ext4 -q ${DISK}6 -L $MODULE -F
}

function show_usage {
	echo "Usage:"
	echo "	sudo ./sd_fusing_artik.sh -d <device> -k <kernel path> -m <modules path> -p <platform path>"
}

function check_partition_format {
	if [ "$FORMAT" != "2" ]; then
		echo " == Skip $DEVICE format =="
		return 0
	fi

	echo " === Start $DEVICE format ==="
	mkpart_3
	echo " === end $DEVICE format ==="
}

function check_args {
	if [ "$DEVICE" == "" ]; then
		echo "$(tput setaf 1) Device node is empty!"
    		tput sgr 0
		show_usage
		exit 0
	fi

	if [ "$DEVICE" != "" ]; then
		echo " * Device: $DEVICE"
	fi

	if [ "$KERNEL" != "" ]; then
		echo " * Kernel: $KERNEL"
	fi

	if [ "$MODULES" != "" ]; then
		echo " * Modules: $MODULES"
	fi

	if [ "$PLATFORM" != "" ]; then
		echo " * Platform: $PLATFORM"
	fi

	if [ "$FORMAT" == "1" ]; then
		echo " * $DEVICE will be formatted, Is it OK? [y/n]"
		read input
		if [ "$input" == "y" ] || [ "$input" == "Y" ]; then
			FORMAT=2
		else
			FORMAT=0
		fi
	fi
}

while test $# -ne 0; do
	option=$1
	shift

	case $option in
	--f|--format)
		FORMAT="1"
		shift
		;;
	-d)
		DEVICE=$1
		shift
		;;
	-k)
		KERNEL=$1
		shift
		;;
	-m)
		MODULES=$1
		shift
		;;
	-p)
		PLATFORM=$1
		shift
		;;
	*)
		;;
	esac
done

check_args
check_partition_format
fuse_image
