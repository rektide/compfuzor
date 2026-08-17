#!/bin/bash
# loop.sh — losetup + mount lifecycle for image files (the kit's loopback tool).
#
# WHY: every "image file" flow (verify a formatted rehearsal image, populate a
# slot, grub-install into an image, inspect mkosi image.raw, identity.sh on
# image partitions) needs the same dance: losetup -fP, find the right
# partition, mount (maybe with subvol=), do the thing, unmount deepest-first,
# losetup -d. This wraps the dance. Real disks (/dev/sda) and online BDR never
# need it — pass those device nodes directly to the other tools.
#
# The universal layout makes the root partition auto-detectable: root is
# ALWAYS the last partition, so `rootdev`/`mount` default to the
# highest-numbered partition of the attached image.
#
# USAGE (needs root for everything except status/--help)
#   loop.sh attach IMG              # losetup -fP --show; idempotent; prints loopdev
#   loop.sh detach IMG|LOOPDEV|all  # refuses while partitions are mounted
#   loop.sh rootdev IMG             # prints root partition dev (or whole loop
#                                   #   if the image has no partition table)
#   loop.sh mount IMG [MNT|auto] [PARTNO] [--subvol S] [--ro]
#                                   # attach + mount. MNT omitted or 'auto' =
#                                   #   first lexically-unused EMPTY
#                                   #   $LOOP_MNT_BASE/loop* dir (never /mnt
#                                   #   itself — mounting there shadows its
#                                   #   submounts); next free name is created
#                                   #   if all existing are used. Default
#                                   #   PARTNO = root partition (last); bare
#                                   #   btrfs mount = DefaultSubvolume = the
#                                   #   dated OS slot; --subvol picks another
#                                   #   — compose facts: --subvol "$(slot.sh os
#                                   #   20250101)". A bare btrfs mount also
#                                   #   PRINTS the default subvol it landed on.
#                                   #   Prints MNT.
#   loop.sh umount MNT|IMG          # unmount submounts deepest-first, then
#                                   #   detach loops that became mount-free
#   loop.sh status                  # every loop device + back-file + mounts
#
# ENV
#   LOOP_MNT_BASE  auto-mount base (default /mnt); candidates are its loop*
#                  dirs in glob (lexical) order
#
# Host deps: util-linux (losetup, findmnt, lsblk), coreutils. Run with sudo.

set -euo pipefail

die()  { printf 'loop: error: %s\n' "$*" >&2; exit 1; }
note() { printf 'loop: %s\n' "$*" >&2; }
usage(){ sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit "${1:-2}"; }

need_root() { [ "$(id -u)" = 0 ] || die "needs root (run with sudo)"; }

LOOP_MNT_BASE="${LOOP_MNT_BASE:-/mnt}"

# First lexically-unused $LOOP_MNT_BASE/loop* dir (glob order = lexical):
# must be a directory, NOT a mountpoint, and EMPTY — both checks matter: an
# unmounted-but-nonempty dir holds data a mount would shadow; a mounted dir
# is in use. If none qualifies, create the next free name (loop, loop0, ...).
pick_mnt() {
  local d
  for d in "$LOOP_MNT_BASE"/loop*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    if [ -z "$(findmnt -n "$d" 2>/dev/null)" ] && [ -z "$(ls -A "$d" 2>/dev/null)" ]; then
      printf '%s' "$d"; return 0
    fi
  done
  if [ ! -e "$LOOP_MNT_BASE/loop" ]; then d="$LOOP_MNT_BASE/loop"
  else
    local n=0
    while [ -e "$LOOP_MNT_BASE/loop$n" ]; do n=$((n+1)); done
    d="$LOOP_MNT_BASE/loop$n"
  fi
  mkdir -p "$d"
  printf '%s' "$d"
}

# loops backing an image (possibly several; prints NAME column)
loops_of_img() { losetup -j "$1" -O NAME -n 2>/dev/null; }

# mounts whose source is a partition of $1 (loopdev)
mounts_of_loop() { findmnt -rn -S "$1" -o TARGET 2>/dev/null; }

attach() {
  need_root
  local img loop
  img="$(realpath "$1")"
  [ -f "$img" ] || die "not a file: $img"
  loop="$(loops_of_img "$img" | head -1)"
  if [ -n "$loop" ]; then
    note "already attached: $loop"
  else
    loop="$(losetup -fP --show "$img")"
    note "attached $img -> $loop"
  fi
  printf '%s\n' "$loop"
}

detach_loop() {  # $1=loopdev; refuses if any partition is mounted
  local m
  for m in $(mounts_of_loop "$1"); do
    die "$1 still has $m mounted (loop.sh umount first)"
  done
  losetup -d "$1"
  note "detached $1"
}

do_detach() {
  need_root
  local t="$1" loops
  if [ "$t" = all ]; then
    loops="$(losetup -O NAME -n 2>/dev/null)" || true
    [ -n "$loops" ] || { note "no loop devices"; return 0; }
    for l in $loops; do detach_loop "$l"; done
    return 0
  fi
  if [ -b "$t" ]; then
    detach_loop "$t"
  else
    loops="$(loops_of_img "$(realpath "$t")")"
    [ -n "$loops" ] || die "no loop device backs $t"
    for l in $loops; do detach_loop "$l"; done
  fi
}

rootdev_of() {  # $1=loopdev -> root partition (last) or the loop itself
  local last
  last="$(lsblk -nrpo NAME,TYPE "$1" 2>/dev/null | awk '$2=="part"{print $1}' | sort -V | tail -1)"
  if [ -n "$last" ]; then printf '%s' "$last"; else printf '%s' "$1"; fi
}

do_mount() {  # IMG [MNT|auto] [PARTNO] [--subvol S] [--ro]
  local img="$1"; shift
  local mnt="" part="" subvol="" ro=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --subvol) subvol="${2:?--subvol needs a SUBVOL}"; shift 2 ;;
      --ro) ro=",ro"; shift ;;
      [0-9]*) part="$1"; shift ;;
      -*) die "unknown mount option: $1" ;;
      *) [ -z "$mnt" ] || die "unexpected extra arg: $1"; mnt="$1"; shift ;;
    esac
  done
  if [ -z "$mnt" ] || [ "$mnt" = auto ]; then
    mnt="$(pick_mnt)"
    note "auto mountpoint: $mnt (first empty unmounted $LOOP_MNT_BASE/loop*)"
  fi
  local loop dev opts fstype
  loop="$(attach "$img")"
  if [ -n "$part" ]; then
    dev="$(lsblk -nrpo NAME,TYPE "$loop" | awk -v p="p$part\$" '$2=="part" && $1 ~ p {print $1; exit}')"
    [ -n "$dev" ] || die "no partition $part on $loop (try: loop.sh rootdev $img)"
  else
    dev="$(rootdev_of "$loop")"
  fi
  fstype="$(lsblk -nrpo FSTYPE "$dev" | head -1)"
  opts="defaults"
  if [ "$fstype" = btrfs ]; then
    [ -n "$subvol" ] && opts="subvol=$subvol$ro"
  else
    [ -n "$subvol" ] && note "note: $dev is not btrfs; --subvol ignored"
  fi
  [ -n "$ro" ] && [ "$opts" = defaults ] && opts="defaults$ro"
  mkdir -p "$mnt"
  mount -t "$fstype" -o "$opts" "$dev" "$mnt"
  note "mounted $dev at $mnt (opts: $opts)"
  # surface the fact a bare btrfs mount relies on: the default-subvol pointer
  # (slot.sh current is the queryable form; slot.sh os computes today's slot)
  if [ "$fstype" = btrfs ] && [ -z "$subvol" ]; then
    p="$(btrfs subvolume get-default "$mnt" 2>/dev/null | sed -n 's/.* path //p')"
    if [ -n "$p" ]; then note "default subvol: /$p"; else note "default subvol: / (top level)"; fi
  fi
  printf '%s\n' "$mnt"
}

do_umount() {
  need_root
  local t="$1" srcs=() m dev
  if [ -d "$t" ]; then
    srcs=("$(findmnt -nro SOURCE "$t")")
    findmnt -R -nro TARGET "$t" 2>/dev/null | sort -r | while read -r m; do
      umount "$m" && note "unmounted $m"
    done
  else
    for dev in $(loops_of_img "$(realpath "$t")"); do
      for m in $(mounts_of_loop "$dev"); do
        srcs+=("$dev"); umount -R "$m" && note "unmounted $m"
      done
    done
  fi
  # detach loops that are now mount-free (only ones WE likely attached)
  for dev in ${srcs[@]+"${srcs[@]}"}; do
    case "$dev" in /dev/loop*) ;; *) continue ;; esac
    if [ -z "$(mounts_of_loop "$dev")" ]; then losetup -d "$dev" && note "detached $dev"; fi
  done
}

do_status() {
  local l back
  printf '%-14s %-40s %s\n' LOOP BACK-FILE MOUNTS
  while IFS= read -r line; do
    l="${line%%:*}"
    back="${line#*:}"; back="${back%%:*}"; back="${back# }"
    printf '%-14s %-40s %s\n' "$l" "$back" "$(mounts_of_loop "$l" | tr '\n' ' ')"
  done < <(losetup -O NAME,BACK-FILE -n 2>/dev/null)
  [ -n "$(losetup -O NAME -n 2>/dev/null)" ] || echo "(no loop devices)"
}

CMD="${1:-}"; shift || true
case "$CMD" in
  attach) [ $# -ge 1 ] || usage; attach "$1" ;;
  detach) [ $# -ge 1 ] || usage; do_detach "$1" ;;
  rootdev)
    need_root
    [ $# -ge 1 ] || usage
    loop="$(attach "$1")"; rootdev_of "$loop" ;;
  mount)  [ $# -ge 1 ] || usage; do_mount "$@" ;;
  umount) [ $# -ge 1 ] || usage; do_umount "$1" ;;
  status) do_status ;;
  -h|--help) usage 0 ;;
  *) die "unknown command: ${CMD:-<none>} (attach|detach|rootdev|mount|umount|status)" ;;
esac
