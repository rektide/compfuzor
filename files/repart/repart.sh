#!/bin/bash
# repart.sh — compose + stamp repart definitions, then drive systemd-repart.
#
# WHY: partition definitions are shared (universal layout + flavor overlays
# in defs/), tokens (@DATE@/@ARCH@/@SWAP@) must be stamped at RUN time, and
# the offline-format / online-migrate flag combos are easy to get wrong.
# This wrapper owns all three: compose (defs + flavor overlay) -> stamp
# (stamp.sh; on-disk scratch, never tmpfs /tmp) -> run (v261+ gated).
#
# Part of the repart kit (files/repart/) — installed as /opt/repart-main by
# repart.opt.pb, pointed at by pivot-bdr/mkosi via REPART_DIR, and burned
# into images (scripts to /usr/local/bin, defs to /usr/local/share/repart-defs).
#
# USAGE
#   repart.sh check
#   repart.sh dry-run <target> [--defs DIR] [--flavor DIR|NAME|none] [-- repart-args]
#   repart.sh format  <target> [flags]    # --offline=yes --empty=force   DESTRUCTIVE
#   repart.sh migrate <target> [flags]    # online BlockDeviceReplace=    DESTRUCTIVE
#                                         #   requires REPART_CONFIRM=yes
#
#   <target>  disk (/dev/sda) or image file (repart loop-attaches files)
#
# DEFS/FLAVOR RESOLUTION
#   defs:   $REPART_DEFS, else probed in order:
#             <script>/../etc/defs/universal.d        (installed: /opt/repart-main)
#             <script>/../share/repart-defs/universal.d (burned image, relative)
#             <script>/defs/universal.d               (repo checkout)
#             /usr/local/share/repart-defs/universal.d  (burned image, absolute)
#   flavor: --flavor DIR (as-is) | NAME (resolved to <defs>/../NAME.d) | none
#           default: format -> format.d ; migrate -> bdr.d ;
#                    dry-run -> $REPART_FLAVOR or format.d
#           The flavor OVERLAYS defs: same-named files replace wholesale
#           (only 50-root.conf differs between flavors today).
#
# UNIVERSAL LAYOUT (defs/universal.d): 1M bios_grub, 384M ESP, fixed @SWAP@
# swap, root LAST (grows; on later disk-growth the tail lands on root).
#
# ENV
#   REPART_DEFS / REPART_FLAVOR / REPART_CONFIRM    (above)
#   REPART_SCRATCH  compose+stamp base (default /var/tmp, NOT tmpfs)
#   REPART_DATE / REPART_ARCH / REPART_SED          (stamp.sh: @DATE@ @ARCH@,
#                   plus extra seds — consumers set e.g. REPART_SED='s|@SWAP@|4G|g')
#   REPART_COMPOSE_ONLY=yes  stop after compose+stamp; print the final defs dir
#                            (testing/debugging — no repart invocation)
#
# Host deps: systemd-repart, coreutils, awk; stamp.sh as sibling or on PATH.

set -euo pipefail

die()  { printf 'repart: error: %s\n' "$*" >&2; exit 1; }
note() { printf 'repart: %s\n' "$*" >&2; }
usage(){ sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit "${1:-2}"; }

MIN_VER=261   # BlockDeviceReplace= floor
SELF="$(cd "$(dirname "$0")" && pwd)"

version_of() { systemd-repart --version 2>/dev/null | awk 'NR==1{print $2}'; }
do_check() {
  command -v systemd-repart >/dev/null 2>&1 || die "systemd-repart not found"
  local ver; ver="$(version_of)"
  [ -n "$ver" ] || die "cannot parse systemd-repart version"
  [ "$ver" -ge "$MIN_VER" ] || die "systemd-repart $ver < $MIN_VER (BlockDeviceReplace= needs v261+)"
  note "systemd-repart $ver >= $MIN_VER OK"
}

stamp_bin() {
  if [ -x "$SELF/stamp.sh" ]; then printf '%s' "$SELF/stamp.sh"
  elif command -v stamp.sh >/dev/null 2>&1; then command -v stamp.sh
  else die "stamp.sh not found (sibling of $0 or on PATH)"
  fi
}

resolve_defs() {
  local d="${REPART_DEFS:-}"
  if [ -z "$d" ]; then
    for c in "$SELF/../etc/defs/universal.d" "$SELF/../share/repart-defs/universal.d" "$SELF/defs/universal.d" "/usr/local/share/repart-defs/universal.d"; do
      [ -d "$c" ] && { d="$c"; break; }
    done
  fi
  [ -n "$d" ] && [ -d "$d" ] || die "no defs dir (set REPART_DEFS or install repart.opt.pb / burn repart-defs)"
  printf '%s' "$d"
}

# resolve_flavor <flavor-arg|auto> <defs> <mode> -> flavor dir or 'none'
resolve_flavor() {
  local arg="$1" defs="$2" mode="$3" d
  if [ "$arg" = none ]; then printf none; return 0; fi
  if [ -z "$arg" ]; then
    case "$mode" in
      migrate) arg=bdr ;;
      format)  arg=format ;;
      dry-run) arg="${REPART_FLAVOR:-format}" ;;
    esac
  fi
  case "$arg" in
    /*|.?/*) d="$arg" ;;                     # explicit path
    *)       d="$(dirname "$defs")/$arg.d" ;; # NAME -> sibling dir
  esac
  [ -d "$d" ] || die "flavor dir not found: $d"
  printf '%s' "$d"
}

# compose <defs> <flavor|none> -> echoes the STAMPED defs dir
# (sets COMPOSED_DIR/STAMPED_DIR globals for the caller's cleanup trap)
compose() {
  local defs="$1" flavor="$2" scratch
  scratch="${REPART_SCRATCH:-/var/tmp}"
  mkdir -p "$scratch"
  COMPOSED_DIR="$(mktemp -d "$scratch/compose.XXXXXX")"
  cp -r "$defs"/. "$COMPOSED_DIR"/
  if [ "$flavor" != none ]; then
    cp -r "$flavor"/. "$COMPOSED_DIR"/        # same-named files replace wholesale
  fi
  ls "$COMPOSED_DIR"/*.conf >/dev/null 2>&1 || die "composed defs have no *.conf (defs=$defs flavor=$flavor)"
  STAMPED_DIR="$(REPART_SCRATCH="$scratch" "$(stamp_bin)" "$COMPOSED_DIR")"
  printf '%s' "$STAMPED_DIR/$(basename "$COMPOSED_DIR")"
}

MODE="${1:-}"; shift || true
TARGET=""; DEFS_ARG=""; FLAVOR_ARG=""; EXTRA=()
case "$MODE" in
  check) do_check; exit 0 ;;
  dry-run|format|migrate) ;;
  -h|--help) usage 0 ;;
  *) die "unknown mode: ${MODE:-<none>} (check|dry-run|format|migrate)" ;;
esac

# parse: first positional = target; --defs/--flavor take values; '--' then raw passthrough
while [ $# -gt 0 ]; do
  case "$1" in
    --defs)    DEFS_ARG="${2:?--defs needs a DIR}"; shift 2 ;;
    --flavor)  FLAVOR_ARG="${2:?--flavor needs DIR|NAME|none}"; shift 2 ;;
    --)        shift; EXTRA+=("$@"); break ;;
    -*)        EXTRA+=("$1"); shift ;;
    *)         [ -z "$TARGET" ] || die "unexpected second target: $1"; TARGET="$1"; shift ;;
  esac
done
[ -n "$TARGET" ] || die "$MODE needs a <target> (disk or image file)"

DEFS="${DEFS_ARG:-$(resolve_defs)}"
[ -d "$DEFS" ] || die "defs dir not found: $DEFS"
FLAVOR="$(resolve_flavor "$FLAVOR_ARG" "$DEFS" "$MODE")"

FINAL="$(compose "$DEFS" "$FLAVOR")"
note "defs: $DEFS + flavor: $FLAVOR -> $FINAL"
if [ "${REPART_COMPOSE_ONLY:-no}" = "yes" ]; then printf '%s\n' "$FINAL"; exit 0; fi
trap 'rm -rf "$COMPOSED_DIR" "$STAMPED_DIR"' EXIT

do_check
case "$MODE" in
  dry-run)
    systemd-repart --definitions="$FINAL" --dry-run=yes "${EXTRA[@]}" "$TARGET"
    ;;
  format)
    note "WIPING partition table on $TARGET (offline format from $FINAL)"
    systemd-repart --definitions="$FINAL" --offline=yes --empty=force --dry-run=no "${EXTRA[@]}" "$TARGET"
    note "formatted $TARGET"
    ;;
  migrate)
    [ "${REPART_CONFIRM:-no}" = "yes" ] || die "migrate is destructive; set REPART_CONFIRM=yes"
    note "WIPING $TARGET and live-migrating via BlockDeviceReplace= (online)"
    systemd-repart --definitions="$FINAL" --empty=force --dry-run=no "${EXTRA[@]}" "$TARGET"
    note "migration done: root now lives on $TARGET"
    ;;
esac
