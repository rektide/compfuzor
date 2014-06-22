#!/bin/sh

set -e

CORES=6
OUTPUT_DIR="{{item.output|default(output)}}"
DEFCONFIG="{{item.defconfig|default(defconfig)|default('')}}"
REPO_DIR="{{repo_dir|default(item.repo_dir)}}"
KERNEL_PARAM_EXTRA="{{item.kernel_param|default(kernel_param)|default('')}}"
KERNEL_TARGET="{{item.kernel_target|default(kernel_target)|default('deb-pkg')}}"
export ARCH="{{item.arch|default(arch)}}"
export CROSS_COMPILE="{{item.cc|default(cc)}}"
export KBUILD_DEBARCH="{{item.debarch}}"
export LOCALVERSION="{{ '-'+item.localversion if item.localversion is defined else '' }}"
export KDEB_PKGVERSION="1.0${LOCALVERSION}"

# "inspired by" and distilled from https://github.com/RobertCNelson/armv7_devel/blob/v3.15.x-sama5-armv7/build_deb.sh
# http://www.spinics.net/lists/linux-kbuild/msg09276.html also shows hope of dtbs_install someday helping
#   but right now i can't seem to get dtb files to bake into the .deb.

cd "${REPO_DIR}"

# clean
#make distclean

#config
[ ! -f .config ] && cp "${DEFCONFIG}" .config && echo "default config copied"

# make
fakeroot make -j${CORES} ${KERNEL_PARAM_EXTRA} ${KERNEL_TARGET}

# extra
{{after_kernel|default(item.after_kernel)|default("")}}

#make distclean
