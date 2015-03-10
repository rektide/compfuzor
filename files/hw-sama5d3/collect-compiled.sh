#!/bin/bash

[ -z "$OUTPUT_DIR" ] && OUTPUT_DIR="{{OUTPUT_DIR}}"
[ -z "$BOARD" ] && BOARD="{{BOARD}}"
[ -z "$UBOOT_DIR" ] && UBOOT_DIR="{{UBOOT_DIR|default(SRCS_DIR+'/repo/uboot')}}"

cp $LINUX_DIR/arch/arm/boot/dts/$BOARD.dtb debian/tmp/boot/vmlinuz* "$OUTPUT_DIR/"
cp $UBOOT_DIR/{spl/u-boot-spl.bin,u-boot.img} "$OUTPUT_DIR/"
cp $AT91BOOT_DIR/sama*bin "$OUTPUT_DIR/"

[ -z "$LINUX_DIR" ] && LINUX_DIR="{{LINUX_DIR}}"
[ -z "$KBUILD_DEBARCH" ] && KBUILD_DEBARCH="{{debarch}}"
[ -z "$REPREPRO_DISTRO" ] && REPREPRO_DISTRO="{{REPREPRO_DISTRO}}"

DEBS_DIR="$(readlink -f $LINUX_DIR)/.."

DEBS=( "linux-image" "linux-headers" "linux-firmware-image" "linux-libc-dev" )
for DEB in ${DEBS[@]}
do
	FILE=${DEBS_DIR}/$( (cd ${DEBS_DIR}; ls -t $DEB*{{debarch}}*deb | head -n1) )
	[ -e "$FILE" ] && ln -sf "$FILE" "$OUTPUT_DIR/"
	reprepro includedeb ${REPREPRO_DISTRO} ${FILE}
done
