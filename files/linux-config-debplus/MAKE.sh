#!/bin/sh
# Pinned kernel package recipe: linux 7.3 development snapshot.
#
# Pin: commit 551c722f40809618230001baccf219193e22fc5a ("Merge tag
# 'rtc-7.3-fixes'", 2026-09-29), 37 commits past release baseline tag
# v7.3-rc5 (72d3fcf802c45d00b300f25b848a93c3a2bd7c7e). Do not substitute a
# moving ref (FETCH_HEAD, HEAD) for the pin.
#
# Usage, from any cwd:  MAKE.sh [SOURCE-TREE]
#
# SOURCE-TREE defaults to /usr/local/src/linux (user-managed). Two accepted
# source forms:
#
# - git checkout: its physical toplevel must BE SOURCE-TREE (no parent-repo
#   discovery) and HEAD must be the pin. Uncommitted files matching
#   HOTFIX_ALLOW are allowed but declared loudly on stderr: the artifact is
#   then base-pin + hotfix, NOT pristine or bit-reproducible. Any other
#   uncommitted change refuses the run. The default allowance is anchored to
#   exactly the four files of the carried AMD patch:
#       drivers/gpu/drm/amd/amdgpu/amdgpu.h
#       drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c
#       drivers/gpu/drm/amd/pm/amdgpu_pm.c
#       drivers/gpu/drm/amd/pm/swsmu/amdgpu_smu.c
#   Override with HOTFIX_ALLOW=<anchored ERE> (grep -E, matched against the
#   porcelain path); note an empty value falls back to this default.
#
# - plain export: must carry a .debplus-source-revision file whose content
#   is the pin. The marker asserts the export's declared base revision
#   only; it is NOT a proof of tree content. Create it explicitly when
#   exporting a verified pin:
#       git -C /usr/local/src/linux archive <pin> | tar -x -C <dir>
#       echo <pin> > <dir>/.debplus-source-revision
#
# Both forms are additionally guarded by the tree's kernelversion.
set -eu

PIN_COMMIT=551c722f40809618230001baccf219193e22fc5a
PIN_TAG=v7.3-rc5
PIN_EPOCH=1790733261
PIN_ISO=2026-09-29T18:54:21-07:00
PIN_KERNELVERSION=7.3.0-rc5
HOTFIX_ALLOW="${HOTFIX_ALLOW:-^drivers/gpu/drm/amd/(amdgpu/(amdgpu\.h|amdgpu_drv\.c)|pm/(amdgpu_pm\.c|swsmu/amdgpu_smu\.c))$}"

die() { echo "MAKE.sh: $*" >&2; exit 1; }

[ $# -le 1 ] || die "usage: MAKE.sh [SOURCE-TREE] (got $# arguments)"

SRC="$(readlink -f "${1:-/usr/local/src/linux}")"

if [ -e "$SRC/.git" ]; then
	[ "$(git -C "$SRC" rev-parse --show-toplevel)" = "$SRC" ] ||
		die "$SRC is not the physical root of its git checkout"
	git -C "$SRC" cat-file -e "$PIN_COMMIT^{commit}" ||
		die "$SRC lacks pinned commit $PIN_COMMIT"
	[ "$(git -C "$SRC" rev-parse HEAD)" = "$PIN_COMMIT" ] ||
		die "$SRC HEAD is not pinned snapshot $PIN_COMMIT ($PIN_TAG + fixes); run against a clean verified-pin export instead"
	# Expected uncommitted hotfix files are allowed but declared; anything
	# else refuses rather than being silently built in or dropped. A git
	# status failure refuses too: never assume a pristine tree.
	dirty="$(git -C "$SRC" status --porcelain)" ||
		die "$SRC: git status failed; refusing to assume a pristine tree"
	if [ -n "$dirty" ]; then
		paths="$(printf '%s\n' "$dirty" | cut -c4-)"
		other="$(printf '%s\n' "$paths" | grep -Ev "$HOTFIX_ALLOW" || true)"
		if [ -n "$other" ]; then
			echo "MAKE.sh: $SRC has uncommitted changes outside the hotfix allowance:" >&2
			printf '%s\n' "$other" >&2
			die "commit, stash, or remove them; they will not be silently built in or dropped"
		fi
		allowed_n="$(printf '%s\n' "$paths" | grep -Ec "$HOTFIX_ALLOW" || true)"
		echo "MAKE.sh: NOTE: $SRC is base pin $PIN_COMMIT plus $allowed_n uncommitted hotfix file(s) (HOTFIX_ALLOW); artifact is NOT pristine/reproducible" >&2
	fi
	SOURCE_DATE_EPOCH="$(git -C "$SRC" show -s --format=%ct "$PIN_COMMIT")"
	KBUILD_BUILD_TIMESTAMP="$(git -C "$SRC" show -s --format=%cI "$PIN_COMMIT")"
	[ "$SOURCE_DATE_EPOCH" = "$PIN_EPOCH" ] ||
		die "pin date constants stale for $PIN_COMMIT"
else
	[ -f "$SRC/.debplus-source-revision" ] ||
		die "unmarked export: plain exports need .debplus-source-revision == $PIN_COMMIT; create it only when exporting a verified pin (see header)"
	rev="$(tr -d ' \t\n\r' < "$SRC/.debplus-source-revision")"
	[ "$rev" = "$PIN_COMMIT" ] ||
		die "export declares base revision '$rev', not pinned $PIN_COMMIT"
	SOURCE_DATE_EPOCH="$PIN_EPOCH"
	KBUILD_BUILD_TIMESTAMP="$PIN_ISO"
fi
[ "$(make -s -C "$SRC" kernelversion)" = "$PIN_KERNELVERSION" ] ||
	die "$SRC is not kernel $PIN_KERNELVERSION (pin mismatch)"
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
