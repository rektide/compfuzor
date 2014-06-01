#!/bin/sh

set -e

CORES=6
SOURCE_DIR="{{source_dir|default(item.source_dir)}}"
#BIN_DIR="{{bins|default(item.bins)|default('')}}"
DEFCONFIG="{{item.config_target|default(config_target)}}"
export ARCH="{{item.arch|default(arch)}}"
export CROSS_COMPILE="{{item.cc|default(cc)}}"
export KBUILD_DEBARCH="{{item.debarch}}"
export LOCALVERSION=-xplain
export KDEB_PKGVERSION=1.0${LOCALVERSION}

# "inspired by" and distilled from https://github.com/RobertCNelson/armv7_devel/blob/v3.15.x-sama5-armv7/build_deb.sh

cd "${SOURCE_DIR}"

# clean
make distclean

#config
#[ ! -f .config ] && cp "${DEFCONFIG}" .config && echo "default config copied"
make "${DEFCONFIG}"

# make
fakeroot make -j"${CORES}" deb-pkg
#fakeroot make -j${CORES} ARCH="${ARCH}" KBUILD_DEBARCH="${DEBARCH} LOCALVERSION=-${BUILD} CROSS_COMPILE=${CC} KDEB_PKGVERSION=${BUILDREV}${DISTRO} deb-pkg