#!/bin/sh

set -e

[ -z "$UBOOT_DIR" ] && export UBOOT_DIR="{{item.repo_dir|default(UBOOT_DIR)}}"
[ -z "$TARGET" ] && export TARGET="{{item.target|default(target)}}"
[ -z "$ARCH" ] && export ARCH="{{item.arch|default(ARCH)}}"
[ -z "$CROSS_COMPILE" ] && export CROSS_COMPILE="{{item.cc|default(CROSS_COMPILE)|default('')}}"
[ -z "OUTPUT" ] && export OUTPUT="{{item.output|default(OUTPUT_DIR)}}"

cd "${UBOOT_DIR}"
make distclean
make "${TARGET}"
make CROSS_COMPILE="${CROSS_COMPILE}"
cp u-boot.bin "${OUTPUT_DIR}.bin"
cp u-boot.img "${OUTPUT_DIR}.img"
cp spl/u-boot-spl.bin "${OUTPUT_DIR}.spl"
#make distclean
