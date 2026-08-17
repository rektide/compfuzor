#!/bin/bash
set -euo pipefail

die() { printf 'repart image: error: %s\n' "$*" >&2; exit 2; }
note() { printf 'repart image: %s\n' "$*" >&2; }
[ "${1:-}" = with ] || die "usage: repart image with IMAGE [--partition NUMBER] [--subvol PATH] [--read-only] [-- COMMAND...]"
shift; [ $# -gt 0 ] || die "image with needs IMAGE"
image="$(realpath -e "$1")"; shift; [ -f "$image" ] || die "not an image file: $image"
partition=""; subvol=""; read_only=false; command=()
while [ $# -gt 0 ]; do
  case "$1" in
    --partition) partition="${2:?--partition needs NUMBER}"; shift 2 ;;
    --subvol) subvol="${2:?--subvol needs PATH}"; shift 2 ;;
    --read-only) read_only=true; shift ;;
    --) shift; command=("$@"); break ;;
    -*) die "unknown option: $1" ;;
    *) die "command must follow --: $1" ;;
  esac
done

loop=""; mountpoint=""
cleanup() {
  status=$?
  if [ -n "$mountpoint" ] && findmnt -rn "$mountpoint" >/dev/null 2>&1; then umount "$mountpoint" || status=$?; fi
  [ -z "$mountpoint" ] || rmdir "$mountpoint" 2>/dev/null || true
  if [ -n "$loop" ]; then losetup -d "$loop" || status=$?; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
loop="$(losetup -fP --show "$image")"
note "attached owned loop $loop"
if [ -n "$partition" ]; then
  case "$partition" in *[!0-9]*|'') die "invalid partition number: $partition" ;; esac
  device="$(lsblk -nrpo NAME,TYPE "$loop" | awk -v n="$partition" '$2=="part" && $1 ~ ("p?" n "$") {print $1; exit}')"
else
  device="$(lsblk -nrpo NAME,PARTTYPE,TYPE "$loop" | awk 'tolower($2) ~ /^(4f68bce3-e8cd-4db1-96e7-fbcaf984b709|b921b045-1df0-41c3-af44-4c6f280d3fae)$/ && $3=="part" {print $1; exit}')"
  if [ -z "$device" ]; then
    device="$(lsblk -nrpo NAME,LABEL,TYPE "$loop" | awk '$2=="root" && $3=="part" {last=$1} END{print last}')"
    [ -n "$device" ] || die "no GPT root partition found; canonical-last fallback requires a partition labeled root"
    last="$(lsblk -nrpo NAME,TYPE "$loop" | awk '$2=="part" {p=$1} END{print p}')"
    [ "$device" = "$last" ] || die "root-labeled partition is not canonical-last"
  fi
fi
[ -n "$device" ] || die "partition not found"
scratch="${REPART_SCRATCH:-/var/tmp}"; mkdir -p "$scratch"
mountpoint="$(mktemp -d "$scratch/repart-image.XXXXXX")"
options=(); [ -z "$subvol" ] || options+=("subvol=$subvol"); $read_only && options+=(ro)
if [ ${#options[@]} -gt 0 ]; then mount -o "$(IFS=,; echo "${options[*]}")" "$device" "$mountpoint"; else mount "$device" "$mountpoint"; fi
note "mounted $device at private mountpoint $mountpoint"
export REPART_IMAGE="$image" REPART_LOOP="$loop" REPART_DEVICE="$device" REPART_MOUNT="$mountpoint"
if [ ${#command[@]} -eq 0 ]; then command=("${SHELL:-/bin/sh}"); fi
set +e
"${command[@]}"
status=$?
set -e
exit "$status"
