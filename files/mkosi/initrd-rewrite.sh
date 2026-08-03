#!/bin/bash
# initrd-rewrite.sh — extract, modify, and repack an initramfs cpio archive.
#
# WHY this exists: an initrd is a build artifact, but it often needs per-host
# specialization AFTER it's built (inject a networkd .network, drop in a script,
# toggle a config). For a Debian-ifupdown VPS the host-specific data lives ON the
# box (in /etc/network/interfaces), so the practical place to specialize the
# initrd is on the VPS itself — exactly what Debian's update-initramfs does for
# /boot/initrd.img. This tool is the generic "crack open an initrd, change files,
# reseal" operator, runnable on the host.
#
# WHAT IT DOES (and why it works): an mkosi-built initrd is a single cpio 'newc'
# archive, gzip/xz/zstd-compressed. We:
#   1. sniff the compression by magic bytes,
#   2. decompress + cpio -idm extract into a temp tree (perms/owners preserved),
#   3. apply --inject (copy files/dirs in) and/or --run (arbitrary shell) edits,
#   4. repack with cpio -H newc and recompress with the SAME algorithm,
#   5. atomically move over the input (or write to -o).
#
# USAGE
#   initrd-rewrite.sh <initrd> [edits...] [-o OUT]
#     --inject SRC[:DST]      copy host SRC into the tree at DST (DST path is
#                             relative to the initrd root; if omitted, DST=SRC).
#                             SRC may be a file or a directory (dirs copied recursively).
#                             Repeatable.
#     --run 'CMD'             run CMD inside the extracted tree (cwd = tree root),
#                             after all --injects. Repeatable. Example:
#                             --run 'echo "vps-seed" > etc/hostname'
#     --list                  don't rewrite; just list the archive contents and exit.
#     -o, --output OUT        write the result to OUT instead of rewriting in place.
#     --compress ALGO[:LVL]   override compression (xz:0-9, gzip:1-9, zstd:1-19,
#                             none). Default: preserve the input's algorithm.
#     -h, --help              show this help.
#
# EXAMPLES
#   # bake networkd config generated from this box's ifupdown into vps-seed.img
#   networkd-static.sh --from-interfaces -o /tmp/net
#   initrd-rewrite.sh /boot/vps-seed.img --inject /tmp/net:/etc/systemd/network
#   # then kexec into /boot/vps-seed.img — it now comes up on the host's own IP
#
#   # peek at what's inside without changing anything
#   initrd-rewrite.sh /boot/vps-seed.img --list
#
#   # drop in a one-liner change
#   initrd-rewrite.sh initrd.img --run 'mkdir -p etc/systemd/network'
#
# CAVEATS
#   * Single cpio only. Some DISTRO initrds (Debian/Ubuntu stock) prepend an
#     UNCOMPRESSED early-cpio microcode blob before the compressed main archive;
#     this tool assumes a single compressed cpio (which is what mkosi emits).
#     For distro /boot/initrd.img with microcode prefixes, use update-initramfs.
#   * UKIs are signed PE binaries — do NOT use this on a UKI (it breaks the
#     signature). This is for cpio initrds.
#   * Repack recompresses at the algorithm's default level unless --compress
#     gives a level; the byte output won't be identical to the original even with
#     no edits (different compression timestamp/level), but is functionally equal.
#
# Host deps: cpio, plus the matching decompressor (gzip | xz | zstd), coreutils.

set -euo pipefail

die() { printf 'initrd-rewrite: %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit "${1:-0}"; }

# --- compression sniff by magic bytes ----------------------------------------
# Returns one of: xz | gzip | zstd | none. We read 6 bytes and match the
# leading magic. cpio 'newc' starts with ASCII "070701" (hex 303730373031);
# anything unrecognized is treated as an uncompressed cpio (none).
detect_comp() {
  local h
  h="$(dd if="$1" bs=6 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  case "$h" in
    fd377a585a00*) echo xz ;;
    1f8b*)         echo gzip ;;
    28b52ffd*)     echo zstd ;;
    *)             echo none ;;   # assume uncompressed cpio (validated on extract)
  esac
}

# decompress stdin -> stdout for the given algo
decompress_for() {
  case "$1" in
    xz)   xz -d -c ;;
    gzip) gzip -d -c ;;
    zstd) zstd -d -c ;;
    none) cat ;;
    *)    die "unknown algo '$1'" ;;
  esac
}

# compress stdin -> stdout for algo[:level]
compress_for() {
  local algo="${1%%:*}" lvl="${1#*:}"
  case "$algo" in
    xz)   [ "$lvl" != "$1" ] && xz -c -"$lvl" || xz -c ;;
    gzip) [ "$lvl" != "$1" ] && gzip -c -"$lvl" || gzip -c ;;
    zstd) [ "$lvl" != "$1" ] && zstd -c -"$lvl" || zstd -c ;;
    none) cat ;;
    *)    die "unknown algo '$algo'" ;;
  esac
}

# --- arg parse ---------------------------------------------------------------
IN=""
OUT=""
LIST=0
COMPRESS=""
INJECTS=()
RUNS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --list)    LIST=1 ;;
    -o|--output) OUT="${2:?--output needs a PATH}"; shift ;;
    --compress)  COMPRESS="${2:?--compress needs ALGO[:LVL]}"; shift ;;
    --inject)
      # SRC[:DST]; split only on the FIRST colon (paths may contain colons rarely)
      inj="${2:?--inject needs SRC[:DST]}"
      case "$inj" in
        *:*) INJECTS+=("${inj%%:*}:${inj#*:}") ;;
        *)   INJECTS+=("$inj:$inj") ;;
      esac
      shift ;;
    --run)   RUNS+=("${2:?--run needs a CMD}"); shift ;;
    --) shift; break ;;
    -*) die "unknown option: $1 (try --help)" ;;
    *)
      [ -z "$IN" ] || die "only one input initrd allowed (already have '$IN')"
      IN="$1" ;;
  esac
  shift
done

[ -n "$IN" ] || { [ $# -gt 0 ] && IN="$1" || die "usage: initrd-rewrite.sh <initrd> [edits...] [-o OUT]"; }
[ -f "$IN" ] || die "input not found: $IN"

# Pick compression: explicit override wins, else sniff the input.
ALGO="${COMPRESS:-$(detect_comp "$IN")}"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# --- extract -----------------------------------------------------------------
# cpio -idmu: create dirs, preserve modes, overwrite. --no-absolute-filenames
# guards against any malicious absolute path inside the archive.
decompress_for "$ALGO" < "$IN" | ( cd "$WORK" && cpio -idmu --no-absolute-filenames >/dev/null 2>&1 ) \
  || die "extract failed (is '$IN' really a $ALGO-compressed cpio initrd?)"

# --- --list: short-circuit ---------------------------------------------------
if [ "$LIST" = 1 ]; then
  ( cd "$WORK" && find . -mindepth 1 | sed 's|^\./||' | sort )
  exit 0
fi

# --- apply --inject (copy host files into the tree) --------------------------
for inj in "${INJECTS[@]+"${INJECTS[@]}"}"; do
  src="${inj%%:*}"; dst="${inj#*:}"
  dst="${dst#/}"   # DST is relative to the initrd root; strip any leading /
  [ -e "$src" ] || { die "--inject: source not found: $src"; }
  if [ -d "$src" ]; then
    # directory: copy its CONTENTS into dst (mkdir dst, cp -a src/. dst)
    mkdir -p "$WORK/$dst"
    cp -a "$src/." "$WORK/$dst/"
  else
    mkdir -p "$WORK/$(dirname "$dst")"
    cp -a "$src" "$WORK/$dst"
  fi
  printf '+ inject %s -> %s\n' "$src" "$dst" >&2
done

# --- apply --run (arbitrary shell, cwd = tree root) --------------------------
for cmd in "${RUNS[@]+"${RUNS[@]}"}"; do
  printf '+ run: %s\n' "$cmd" >&2
  ( cd "$WORK" && sh -c "$cmd" ) || die "--run failed: $cmd"
done

# --- repack + recompress -----------------------------------------------------
# cpio 'newc' format. find -print0 | cpio --null preserves names with odd chars.
# Output goes to a temp file next to the final destination, then atomically moved
# so a failed/aborted rewrite never leaves a half-written initrd.
DEST="${OUT:-$IN}"
TMP_OUT="$(mktemp "${DEST}.XXXXXX")"
( cd "$WORK" && find . -mindepth 1 -print0 | cpio --null -o -H newc 2>/dev/null ) \
  | compress_for "$ALGO" > "$TMP_OUT" || { rm -f "$TMP_OUT"; die "repack failed"; }

mv -f "$TMP_OUT" "$DEST"
printf 'wrote %s (%s)\n' "$DEST" "$ALGO" >&2
