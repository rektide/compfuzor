#!/bin/sh

set -e

[ -z "$UBOOT_DIR" ] && export UBOOT_DIR="{{item.repo_dir|default(UBOOT_DIR)|default(SRCS_DIR+'/uboot')}}"
[ -z "$TARGET" ] && export TARGET="{{item.target|default(target)}}"
[ -z "$ARCH" ] && export ARCH="{{item.arch|default(ARCH)}}"
[ -z "$CROSS_COMPILE" ] && export CROSS_COMPILE="{{item.cc|default(CROSS_COMPILE)|default('')}}"
[ -z "$OUTPUT_DIR" ] && export OUTPUT_DIR="{{item.output|default(OUTPUT_DIR)}}"
[ -z "$FLAVOR" ] && export FLAVOR="{{ item.flavor|default(FLAVOR)|default('') }}"

cd "$UBOOT_DIR"
make distclean
make "$TARGET"
make CROSS_COMPILE="$CROSS_COMPILE"

cp u-boot.bin "$OUTPUT_DIR/u-boot$FLAVOR.bin"
cp u-boot.img "$OUTPUT_DIR/u-boot$FLAVOR.img"
cp spl/u-boot-spl.bin "$OUTPUT_DIR/u-boot-spl$FLAVOR.bin"
#make distclean
