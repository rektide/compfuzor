#!/bin/bash
# repart.sh — systemd-repart invocation wrapper with a version gate.
#
# WHY: the offline-format / online-migrate / dry-run flag combinations are
# easy to get wrong and were drifting between playbooks. This centralizes
# them plus the v261+ gate (BlockDeviceReplace= needs systemd >= 261 — a
# --help grep is NOT a version check).
#
# Part of the repart kit (files/repart/) — see stamp.sh for the sharing story.
#
# USAGE
#   repart.sh check                  # verify systemd-repart >= 261, exit 1 if not
#   repart.sh dry-run <target> <defs> [--offline]
#   repart.sh format  <target> <defs>          # --offline=yes --empty=force (DESTRUCTIVE)
#   repart.sh migrate <target> <defs>          # online --empty=force   (DESTRUCTIVE)
#
#   <target>  disk (/dev/sda) or image file (repart loop-attaches files)
#   <defs>    definitions dir (usually a stamp.sh output)
#   format/migrate WIPE the target's partition table. migrate additionally
#   requires REPART_CONFIRM=yes (the live BDR operation is near-irreversible).
#
# ENV
#   REPART_CONFIRM  "yes" to allow migrate (default: no -> abort)
#   REPART_OFFLINE  "yes"/"no" default offline-ness for dry-run (default: online)
#   extra args after <defs> are passed through to systemd-repart.
#
# Host deps: systemd-repart, coreutils, awk.

set -euo pipefail

die()  { printf 'repart: error: %s\n' "$*" >&2; exit 1; }
note() { printf 'repart: %s\n' "$*" >&2; }

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit "${1:-2}"; }

# minimum systemd version for BlockDeviceReplace= (and this kit's flag combos)
MIN_VER=261

version_of() { systemd-repart --version 2>/dev/null | awk 'NR==1{print $2}'; }

do_check() {
  command -v systemd-repart >/dev/null 2>&1 || die "systemd-repart not found"
  local ver; ver="$(version_of)"
  [ -n "$ver" ] || die "cannot parse systemd-repart version"
  [ "$ver" -ge "$MIN_VER" ] || die "systemd-repart $ver < $MIN_VER (BlockDeviceReplace= needs v261+)"
  note "systemd-repart $ver >= $MIN_VER OK"
}

MODE="${1:-}"; shift || true
case "$MODE" in
  check) do_check ;;
  dry-run)
    [ $# -ge 2 ] || usage
    TARGET="$1"; DEFS="$2"; shift 2
    do_check
    OFFLINE="${REPART_OFFLINE:-no}"
    systemd-repart --definitions="$DEFS" --dry-run=yes "--offline=$OFFLINE" "$@" "$TARGET"
    ;;
  format)
    [ $# -ge 2 ] || usage
    TARGET="$1"; DEFS="$2"; shift 2
    do_check
    note "WIPING partition table on $TARGET (offline format from $DEFS)"
    systemd-repart --definitions="$DEFS" --offline=yes --empty=force --dry-run=no "$@" "$TARGET"
    note "formatted $TARGET"
    ;;
  migrate)
    [ $# -ge 2 ] || usage
    TARGET="$1"; DEFS="$2"; shift 2
    do_check
    [ "${REPART_CONFIRM:-no}" = "yes" ] || die "migrate is destructive; set REPART_CONFIRM=yes"
    note "WIPING $TARGET and live-migrating via BlockDeviceReplace= (online)"
    systemd-repart --definitions="$DEFS" --empty=force --dry-run=no "$@" "$TARGET"
    note "migration done: root now lives on $TARGET"
    ;;
  -h|--help) usage 0 ;;
  *) die "unknown mode: ${MODE:-<none>} (check|dry-run|format|migrate)" ;;
esac
