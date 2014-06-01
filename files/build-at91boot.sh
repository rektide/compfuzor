#!/bin/sh

set -e

SOURCE_DIR="{{source_dir|default(item.source_dir)}}"
TARGET="{{target|default(item.target)}}"
ARCH="{{arch|default(item.arch)}}"
CC="{{cc|default(item.cc)}}"
BIN_DIR="{{bins|default(item.bins)}}"

cd "${SOURCE_DIR}"
make mrproper
make "${TARGET}"
make ARCH="${ARCH}" CROSS_COMPILE="${CC}"
cp binaries/* "${BIN_DIR}/"
make mrproper
