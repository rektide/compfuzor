#!/bin/bash

[ -z "$OUTPUT_DIR" ] && OUTPUT_DIR="{{OUTPUT_DIR}}"
[ -z "$BOARD" ] && BOARD="{{BOARD}}"
[ -z "$UBOOT_DIR" ] && UBOOT_DIR="{{UBOOT_DIR|default(SRCS_DIR+'/repo/uboot')}}"
[ -z "$LINUX_DIR" ] && LINUX_DIR="{{LINUX_DIR}}"
[ -z "$DEBS_DIR" ] && DEBS_DIR="$(readlink -f $LINUX_DIR)/.."
[ -z "$KBUILD_DEBARCH" ] && KBUILD_DEBARCH="{{debarch}}"
[ -z "$REPREPRO_DISTRO" ] && REPREPRO_DISTRO="{{REPREPRO_DISTRO}}"
[ -z "$AT91BOOT_DIR" ] && AT91BOOT_DIR="{{AT91BOOT_DIR}}"
[ -z "$UBOOT_DIR" ] && UBOOT_DIR="{{UBOOT_DIR}}"

cd $OUTPUT_DIR


# uboot
UBOOT_BINS=( "spl/u-boot-spl.bin" "u-boot.img" "u-boot.bin" )
for UBOOT_BIN in ${UBOOT_BINS[@]}
do
	[ -f "$UBOOT_DIR/$UBOOT_BIN" ] && cp "$UBOOT_DIR/$UBOOT_BIN" .
done


# at91boot
[ -n "$(shopt -s nullglob; ls $AT91BOOT_DIR/binaries/sama*bin)" ] && cp $AT91BOOT_DIR/binaries/sama*bin .


# kernel
DEBS=( "linux-image" "linux-headers" "linux-firmware-image" "linux-libc-dev" )
for DEB in ${DEBS[@]}
do
	FILE=${DEBS_DIR}/$( (cd ${DEBS_DIR}; ls -t $DEB*${KBUILD_DEBARCH}*deb | head -n1) )
	[ -e "$FILE" ] && ln -sf "$FILE" "$OUTPUT_DIR/"

	[ -z "REPREPRO_BYPASS" ] && reprepro includedeb ${REPREPRO_DISTRO} ${FILE}
done

LATEST_DEB=$( (cd $DEBS_DIR ; ls -t linux-image*${KBUILD_DEBARCH}*deb | head -n1 ) )
VMLINUZ_DEB=$( dpkg -c $DEBS_DIR/$LATEST_DEB | grep 'boot/vmlinuz' | awk '{print $6}' )
dpkg --fsys-tarfile $DEBS_DIR/$LATEST_DEB | tar x --wildcards --strip-components=2 -f - "./boot/vmlinuz*"
ln -sf $LATEST_DEB vmlinuz-latest

cp $LINUX_DIR/arch/arm/boot/dts/$BOARD.dtb .
