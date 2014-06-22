#!/bin/sh

set -e

REPO_DIR="{{item.repo_dir|default(repo_dir)}}"
TARGET="{{item.target|default(target)}}"
ARCH="{{item.arch|default(arch)}}"
CC="{{item.cc|default(cc)}}"
OUTPUT="{{item.output|default(output)}}"

cd "${REPO_DIR}"
make mrproper
make "${TARGET}"
make ARCH="${ARCH}" CROSS_COMPILE="${CC}"
cp binaries/sama5d3*bin "${OUTPUT}.bin"
make mrproper
