#!/bin/sh

set -e

REPO_DIR="{{item.repo_dir|default(repo_dir)}}"
TARGET="{{item.target|default(target)}}"
ARCH="{{item.arch|default(arch)}}"
CC="{{cc|default(item.cc)}}"
OUTPUT="{{item.output|default(output)}}"

cd "${REPO_DIR}"
make distclean
make "${TARGET}"
make CROSS_COMPILE="${CC}"
cp u-boot.bin "${OUTPUT}.bin"
cp u-boot.img "${OUTPUT}.img"
cp spl/u-boot-spl.bin "${OUTPUT}.spl"
#make distclean
