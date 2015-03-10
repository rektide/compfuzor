#!/bin/sh

set -e

[ -z "$AT91BOOT_DIR" ] && AT91BOOT_DIR="{{item.repo_dir|default(AT91BOOT_DIR)|default(SRCS_DIR+'/at91boot')}}"
[ -z "$TARGET" ] && TARGET="{{item.target|default(TARGET)}}"
[ -z "$ARCH" ] && ARCH="{{item.arch|default(ARCH)}}"
[ -z "$CROSS_COMPILE" ] && CROSS_COMPILE="{{item.cc|default(CROSS_COMPILE)}}"
[ -z "$OUTPUT_DIR" ] && OUTPUT_DIR="{{item.output|default(OUTPUT_DIR)}}"

cd "${AT91BOOT_DIR}"
make mrproper
make "${TARGET}"
make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}"
cp binaries/sama5d3*bin "${OUTPUT_DIR}/"
make mrproper
