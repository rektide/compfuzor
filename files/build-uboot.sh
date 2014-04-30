#!/bin/sh

SOURCE_DIR="{{source_dir|default(item.source_dir)}}"
TARGET="{{target|default(item.target)}}"
ARCH="{{arch|default(item.arch)}}"
CC="{{cc|default(item.cc)}}"
BIN="{{bin|default(item.bin)}}"

cd "${SOURCE_DIR}"
make distclean
make "${TARGET}"
make ARCH="${ARCH}" CROSS_COMPILE="${CC}"
cp u-boot.bin "${BIN}"
make distclean
