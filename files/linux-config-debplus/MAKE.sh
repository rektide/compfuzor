#!/bin/sh
# Pinned kernel package recipe: linux 7.3 development snapshot.
#
# Pin: commit 551c722f40809618230001baccf219193e22fc5a ("Merge tag
# 'rtc-7.3-fixes'", 2026-09-29), 37 commits past release baseline tag
# v7.3-rc5 (72d3fcf802c45d00b300f25b848a93c3a2bd7c7e). Do not substitute a
# moving ref (FETCH_HEAD, HEAD) for the pin.
#
# Usage, from any cwd:  MAKE.sh [SOURCE-TREE]
# SOURCE-TREE defaults to /usr/local/src/linux (user-managed). The tree must
# actually BE the pinned snapshot: a git checkout is refused unless its HEAD
# is the pin, and a plain export is refused unless its Makefile carries the
# pinned kernel version. The default checkout usually sits elsewhere; export
# the pin to a clean tree (git archive) and run this recipe against that.
set -eu

PIN_COMMIT=551c722f40809618230001baccf219193e22fc5a
PIN_TAG=v7.3-rc5
PIN_EPOCH=1790733261
PIN_ISO=2026-09-29T18:54:21-07:00
PIN_KERNELVERSION=7.3.0-rc5

SRC="$(readlink -f "${1:-/usr/local/src/linux}")"
if [ -e "$SRC/.git" ]; then
	git -C "$SRC" cat-file -e "$PIN_COMMIT^{commit}" || {
		echo "MAKE.sh: $SRC lacks pinned commit $PIN_COMMIT" >&2
		exit 1
	}
	head_commit="$(git -C "$SRC" rev-parse HEAD)"
	if [ "$head_commit" != "$PIN_COMMIT" ]; then
		echo "MAKE.sh: $SRC HEAD $head_commit is not pinned snapshot $PIN_COMMIT ($PIN_TAG + fixes)." >&2
		echo "MAKE.sh: run against a clean export of the pin instead." >&2
		exit 1
	fi
	SOURCE_DATE_EPOCH="$(git -C "$SRC" show -s --format=%ct "$PIN_COMMIT")"
	KBUILD_BUILD_TIMESTAMP="$(git -C "$SRC" show -s --format=%cI "$PIN_COMMIT")"
	if [ "$SOURCE_DATE_EPOCH" != "$PIN_EPOCH" ]; then
		echo "MAKE.sh: pin date constants stale for $PIN_COMMIT" >&2
		exit 1
	fi
else
	# Portable export of the pin: reproducibility metadata from the pinned
	# commit, not from export mtimes or wall clock.
	SOURCE_DATE_EPOCH="$PIN_EPOCH"
	KBUILD_BUILD_TIMESTAMP="$PIN_ISO"
fi
if [ "$(make -s -C "$SRC" kernelversion)" != "$PIN_KERNELVERSION" ]; then
	echo "MAKE.sh: $SRC is not kernel $PIN_KERNELVERSION (pin mismatch)" >&2
	exit 1
fi
export SOURCE_DATE_EPOCH KBUILD_BUILD_TIMESTAMP
export KBUILD_BUILD_USER=rektide KBUILD_BUILD_HOST=workhorse
export DPKG_DEB_COMPRESSOR_TYPE=xz
export DPKG_DEB_COMPRESSOR_LEVEL=9
export DPKG_DEB_THREADS_MAX=12
export KDEB_CHANGELOG_DIST=unstable

cd "$SRC"
make \
  -j12 \
  LLVM=1 \
  LOCALVERSION=-debplus.1 \
  KDEB_SOURCENAME=linux-debplus \
  KDEB_PKGVERSION=7.3.0~rc5+git20260929.551c722f4080-1 \
  KDEB_CHANGELOG_DIST=unstable \
  bindeb-pkg
