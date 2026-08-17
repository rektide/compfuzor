#!/bin/bash
# repart.sh — drive systemd-repart with the right flags, nothing else.
#
# A deliberately THIN front door: defs/flavor/stamping lives in compose.sh,
# loopback in loop.sh, subvolumes in slot.sh. This wrapper adds only what is
# repart-specific: the v261+ gate, the mode→flag table, and a plan banner.
# Stepping by hand: compose.sh → systemd-repart → loop.sh → slot.sh.
#
# USAGE
#   repart.sh check
#   repart.sh dry-run <target> [--defs DIR] [--flavor DIR|NAME|none] [-- repart-args]
#   repart.sh format  <target> [flags]    # --offline=yes --empty=force   DESTRUCTIVE
#   repart.sh migrate <target> [flags]    # online BlockDeviceReplace=    DESTRUCTIVE
#                                         #   requires REPART_CONFIRM=yes
#
#   <target>  disk (/dev/sda) or image file (for images see loop.sh afterwards)
#   dry-run previews EXACTLY what format/migrate do (--empty=force too) with
#   zero writes (repart gates every write path on --dry-run=yes).
#
# ENV: everything compose.sh takes (REPART_DEFS/FLAVOR/SCRATCH/SWAP/SED/DATE/
# ARCH) plus REPART_CONFIRM for migrate.
#
# Host deps: systemd-repart; compose.sh as sibling or on PATH.

set -euo pipefail

die()  { printf 'repart: error: %s\n' "$*" >&2; exit 1; }
note() { printf 'repart: %s\n' "$*" >&2; }
usage(){ sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit "${1:-2}"; }

MIN_VER=261   # BlockDeviceReplace= floor

compose_bin() {
  local self; self="$(cd "$(dirname "$0")" && pwd)"
  if [ -x "$self/compose.sh" ]; then printf '%s' "$self/compose.sh"
  elif command -v compose.sh >/dev/null 2>&1; then command -v compose.sh
  else die "compose.sh not found (sibling of $0 or on PATH)"
  fi
}

version_of() { systemd-repart --version 2>/dev/null | awk 'NR==1{print $2}'; }
do_check() {
  command -v systemd-repart >/dev/null 2>&1 || die "systemd-repart not found"
  local ver; ver="$(version_of)"
  [ -n "$ver" ] || die "cannot parse systemd-repart version"
  [ "$ver" -ge "$MIN_VER" ] || die "systemd-repart $ver < $MIN_VER (BlockDeviceReplace= needs v261+)"
  note "systemd-repart $ver >= $MIN_VER OK"
}

# Compact plan banner so repart's own verbose output has a frame.
banner() {  # $1=mode $2=target $3=final-defs
  local f type size
  printf '== repart %s: %s\n' "$1" "$2"
  for f in "$3"/*.conf; do
    type="$(awk -F= '/^Type=/{print $2; exit}' "$f")"
    case "$type" in 21686148-*) type=bios-grub ;; esac
    size="$(awk -F= '/^SizeMinBytes=/{print $2; exit}' "$f")"
    printf '   %-14s %-28s min %s\n' "$(basename "$f" .conf)" "$type" "${size:--}"
  done
  awk -F= '/^DefaultSubvolume=/{printf "   %-14s %s\n", "default-subvol", $2; exit}' "$3/50-root.conf" 2>/dev/null
  printf '   (systemd-repart output follows; scratch auto-removed on exit)\n'
}

MODE="${1:-}"; shift || true
TARGET=""; DEFS_ARG=""; FLAVOR_ARG=""; REXTRA=()   # REXTRA: raw passthrough to systemd-repart
case "$MODE" in
  check) do_check; exit 0 ;;
  dry-run|format|migrate) ;;
  -h|--help) usage 0 ;;
  *) die "unknown mode: ${MODE:-<none>} (check|dry-run|format|migrate)" ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --defs)    DEFS_ARG="${2:?--defs needs a DIR}"; shift 2 ;;
    --flavor)  FLAVOR_ARG="${2:?--flavor needs DIR|NAME|none}"; shift 2 ;;
    --)        shift; REXTRA+=("$@"); break ;;
    -*)        REXTRA+=("$1"); shift ;;
    *)         [ -z "$TARGET" ] || die "unexpected second target: $1"; TARGET="$1"; shift ;;
  esac
done
[ -n "$TARGET" ] || die "$MODE needs a <target> (disk or image file)"

# mode default flavor (compose.sh defaults to format; migrate is the exception)
FLAVOR="$FLAVOR_ARG"
if [ -z "$FLAVOR" ] && [ "$MODE" = migrate ]; then FLAVOR=bdr; fi

CARGS=()
[ -n "$DEFS_ARG" ]  && CARGS+=(--defs "$DEFS_ARG")
[ -n "$FLAVOR" ]    && CARGS+=(--flavor "$FLAVOR")
FINAL="$("$(compose_bin)" ${CARGS[@]+"${CARGS[@]}"})" || die "compose failed"
trap 'rm -rf "$(dirname "$FINAL")"' EXIT
do_check
banner "$MODE" "$TARGET" "$FINAL"
case "$MODE" in
  dry-run)
    # --empty=force MIRRORS format/migrate so the preview shows the real WIPE
    # plan (zero writes: --dry-run=yes gates every write path in repart).
    systemd-repart --definitions="$FINAL" --dry-run=yes --empty=force "${REXTRA[@]}" "$TARGET"
    ;;
  format)
    note "WIPING partition table on $TARGET (offline format from $FINAL)"
    systemd-repart --definitions="$FINAL" --offline=yes --empty=force --dry-run=no "${REXTRA[@]}" "$TARGET"
    note "formatted $TARGET (next: loop.sh mount for images, slot.sh verify)"
    ;;
  migrate)
    [ "${REPART_CONFIRM:-no}" = "yes" ] || die "migrate is destructive; set REPART_CONFIRM=yes"
    note "WIPING $TARGET and live-migrating via BlockDeviceReplace= (online)"
    systemd-repart --definitions="$FINAL" --empty=force --dry-run=no "${REXTRA[@]}" "$TARGET"
    note "migration done: root now lives on $TARGET (next: slot.sh default)"
    ;;
esac
