#!/bin/bash

set -e

[ -z "$CONCURRENCY_LEVEL" ] && export CONCURRENCY_LEVEL="{{CONCURRENCY_LEVEL|default('$(nproc)')}}"
[ -z "$OUTPUT_DIR" ] && export OUTPUT_DIR="{{item.output|default(OUTPUT_DIR)|default(VAR)}}"
[ -z "$LINUX_DEFCONFIG" ] && export DEFCONFIG="{{item.defconfig|default(LINUX_DEFCONFIG)|default(VAR+'/kernel-defconfig')}}"
[ -z "$LINUX_DIR" ] && export LINUX_DIR="{{item.repo_dir|default(LINUX_DIR)|default(SRCS_DIR+'/linux')}}"
[ -z "$LINUX_PARAM_EXTRA" ] && export LINUX_PARAM_EXTRA="{{item.kernel_param|default(LINUX_PARAM_EXTRA)|default('')}}"
[ -z "$LINUX_TARGET" ] && export LINUX_TARGET="{{item.target|default(LINUX_TARGET)|default('deb-pkg')}}"
[ -z "$ARCH" ] && export ARCH="{{item.arch|default(ARCH)}}"
[ -z "$CROSS_COMPILE" ] && export CROSS_COMPILE="{{item.cc|default(CROSS_COMPILE)}}"
[ -z "$KBUILD_DEBARCH" ] && export KBUILD_DEBARCH="{{item.debarch|default(KBUILD_DEBARCH)}}"
[ -z "$KDEB_PKGVERSION" ] && export KDEB_PKGVERSION="{{ item.pkgversion|default(KDEB_PKGVERSION)|default('1.0')}}"

# "inspired by" and distilled from https://github.com/RobertCNelson/armv7_devel/blob/v3.15.x-sama5-armv7/build_deb.sh
# http://www.spinics.net/lists/linux-kbuild/msg09276.html also shows hope of dtbs_install someday helping
#   but right now i can't seem to get dtb files to bake into the .deb.

cd "${LINUX_DIR}"

# clean
#make distclean

#config
[ ! -f .config ] && cp "${LINUX_DEFCONFIG}" .config && echo "default config copied"

# make
time make ARCH=$ARCH $LINUX_PARAM_EXTRA $LINUX_TARGET

# extra
{{item.after_kernel|default(LINUX_AFTER)|default("")}}

#make distclean
