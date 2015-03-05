#!/bin/bash

[ -z "$LINUX_DIR" ] && LINUX_DIR="{{LINUX_DIR}}"
[ -z "$OUTPUT_DIR" ] && OUTPUT_DIR="{{OUTPUT_DIR}}"
[ -z "$KBUILD_DEBARCH" ] && KBUILD_DEBARCH="{{debarch}}"
[ -z "$REPREPRO_DISTRO" ] && REPREPRO_DISTRO="{{REPREPRO_DISTRO}}"
[ -z "$BOARD" ] && BOARD="{{BOARD}}"

DEBS_DIR="$(readlink -f $LINUX_DIR)/.."

DEBS=( "linux-image" "linux-headers" "linux-firmware-image" "linux-libc-dev" )
for DEB in ${DEBS[@]}
do
	FILE=${DEBS_DIR}/$( (cd ${DEBS_DIR}; ls -t "$DEB*{{debarch}}*deb" | head -n1) )
	[ -e "$FILE" ] && ln -s "$FILE" "$OUTPUT_DIR/"
	reprepro includedeb ${REPREPRO_DISTRO} ${FILE}
done

cp $LINUX_DIR/arch/arm/boot/dts/$BOARD.dtb debian/tmp/boot/vmlinuz* "${OUTPUT_DIR}/
