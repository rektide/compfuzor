#!/bin/bash
# slot.sh — dated OS/home subvolume slot lifecycle on a btrfs filesystem.
#
# WHY: the dated-slot scheme (/os/superbfowle/<arch>/<yyyymmdd> as the default
# subvol + /home/superbfowle/<yyyymmdd>) gives A/B-style OS management on
# plain btrfs: a new install is a new dated slot, rollback is flipping the
# default back. The verbs here were previously inline in pivot-bdr's bins.
#
# Part of the repart kit (files/repart/) — see stamp.sh for the sharing story.
#
# USAGE
#   slot.sh paths [date]           # print the scheme's paths for a date
#   slot.sh list <mnt>             # list dated slots (os + home)
#   slot.sh default <mnt> [path]   # set default subvol: exact path, or (no
#                                  #   arg) newest slot under the os prefix
#   slot.sh flip <mnt> <date|path> # switch default to another dated slot
#   slot.sh verify <mnt>           # show default subvol + slot inventory
#
#   <path> args accept leading slash or not; <date> is YYYYMMDD.
#
# ENV (the scheme — kit-owned defaults, override per host)
#   REPART_OS_PREFIX    default /os/superbfowle
#   REPART_HOME_PREFIX  default /home/superbfowle
#   REPART_ARCH         default: uname -m mapped (x86_64->amd64, aarch64->arm64)
#   REPART_DATE         default date for `paths` (default: today)
#
# Host deps: btrfs-progs, coreutils, awk. Mounted btrfs at <mnt> required for
# all verbs except `paths`.

set -euo pipefail

die()  { printf 'slot: error: %s\n' "$*" >&2; exit 1; }
note() { printf 'slot: %s\n' "$*"; }
usage(){ sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit "${1:-2}"; }

OS_PREFIX="${REPART_OS_PREFIX:-/os/superbfowle}"
HOME_PREFIX="${REPART_HOME_PREFIX:-/home/superbfowle}"
ARCH="${REPART_ARCH:-$(case "$(uname -m)" in x86_64) echo amd64 ;; aarch64) echo arm64 ;; *) uname -m ;; esac)}"
DATE_DEFAULT="${REPART_DATE:-$(date +%Y%m%d)}"

norm() { local p="$1"; case "$p" in /*) printf '%s' "$p" ;; *) printf '/%s' "$p" ;; esac; }
denorm() { local p="$(norm "$1")"; printf '%s' "${p#/}"; }

slot_of_date() { printf '%s/%s/%s' "$OS_PREFIX" "$ARCH" "$1"; }

# list subvol paths (denormalized) under a prefix, newest-created first
slots_under() {  # $1=mnt $2=prefix
  btrfs subvolume list --sort=-ogen "$1" 2>/dev/null \
    | awk -v p="$(denorm "$2")/" 'index($NF, p)==1 {print $NF}'
}

# resolve $2 (path or date) to a full slot path; empty if not a slot/date
resolve_arg() {  # $1=mnt(not used) $2=arg
  case "$2" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) slot_of_date "$2" ;;
    *) norm "$2" ;;
  esac
}

need_mnt() { [ -d "$1" ] || die "not a directory: $1 (mounted btrfs root?)"; }

set_default() {  # $1=mnt $2=slot-path(absolute)
  local id
  id="$(btrfs subvolume list "$1" | awk -v s="$(denorm "$2")" '$NF==s{print $2; exit}')"
  [ -n "$id" ] || die "subvolume '$2' not found under $1"
  btrfs subvolume set-default "$id" "$1"
  note "default subvol -> $2 (id $id)"
}

CMD="${1:-}"; shift || true
case "$CMD" in
  paths)
    D="${1:-$DATE_DEFAULT}"
    case "$D" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) die "bad date '$D' (want YYYYMMDD)" ;; esac
    printf 'os=%s\nhome=%s/%s\n' "$(slot_of_date "$D")" "$HOME_PREFIX" "$D"
    ;;
  list)
    [ $# -ge 1 ] || usage; M="$1"; need_mnt "$M"
    echo "os slots (newest first):";   slots_under "$M" "$OS_PREFIX"   | sed 's/^/  /'
    echo "home slots (newest first):"; slots_under "$M" "$HOME_PREFIX" | sed 's/^/  /'
    ;;
  default)
    [ $# -ge 1 ] || usage; M="$1"; need_mnt "$M"
    if [ -n "${2:-}" ]; then
      TARGET="$(resolve_arg "$M" "$2")"
      btrfs subvolume show "$M$TARGET" >/dev/null 2>&1 || die "slot $TARGET not present under $M"
      set_default "$M" "$TARGET"
    else
      NEWEST="$(slots_under "$M" "$OS_PREFIX" | head -1)"
      [ -n "$NEWEST" ] || die "no slots under $OS_PREFIX on $M"
      set_default "$M" "/$NEWEST"
    fi
    ;;
  flip)
    [ $# -ge 2 ] || usage; M="$1"; need_mnt "$M"
    TARGET="$(resolve_arg "$M" "$2")"
    btrfs subvolume show "$M$TARGET" >/dev/null 2>&1 || die "slot $TARGET not present under $M"
    set_default "$M" "$TARGET"
    note "(rollback = flip back; slots are never deleted by this tool)"
    ;;
  verify)
    [ $# -ge 1 ] || usage; M="$1"; need_mnt "$M"
    echo "default subvol:"; btrfs subvolume get-default "$M" | sed 's/^/  /'
    echo "slots:"; { slots_under "$M" "$OS_PREFIX"; slots_under "$M" "$HOME_PREFIX"; } | sed 's/^/  /'
    ;;
  -h|--help) usage 0 ;;
  *) die "unknown command: ${CMD:-<none>} (paths|list|default|flip|verify)" ;;
esac
