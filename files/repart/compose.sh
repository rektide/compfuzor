#!/bin/bash
# compose.sh — resolve defs + flavor overlay, copy to scratch, stamp tokens.
#
# WHY: this was hidden inside repart.sh; extracted so the pipeline is steppable
# by hand — compose.sh (make the defs) → repart.sh (run repart) → loop.sh
# (attach/mount) → slot.sh (subvolumes). Each stage is independently runnable
# and inspectable.
#
# USAGE
#   compose.sh [--defs DIR] [--flavor DIR|NAME|none]
#   stdout: the FINAL stamped defs dir. Contract: on success the pre-stamp
#   compose copy is already removed — the ONLY artifact is the stamped tree;
#   the caller owns `rm -rf "$(dirname "$FINAL")"` when done.
#
# FLAVOR RESOLUTION
#   DIR (as-is) | NAME (resolved to <defs>/../NAME.d) | none (base universal)
#   default: format
#
# ENV (all optional)
#   REPART_DEFS     default defs dir (else probed: <script>/../etc/defs,
#                   <script>/../share/repart-defs, <script>/defs,
#                   /usr/local/share/repart-defs — installed/burned/repo)
#   REPART_FLAVOR   default flavor name
#   REPART_SCRATCH  scratch base (default /var/tmp — on-disk, NOT tmpfs)
#   REPART_SWAP     @SWAP@ stamp (default 4G)
#   REPART_SED      extra sed(s), PREPENDED so they win over the swap default
#   REPART_DATE / REPART_ARCH  @DATE@ / @ARCH@ stamps (stamp.sh)
#
# Host deps: coreutils; stamp.sh as sibling or on PATH.

set -euo pipefail

die()  { printf 'compose: error: %s\n' "$*" >&2; exit 1; }
note() { printf 'compose: %s\n' "$*" >&2; }
usage(){ sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit "${1:-2}"; }

SELF="$(cd "$(dirname "$0")" && pwd)"

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

resolve_flavor() {
  local arg="${1:-${REPART_FLAVOR:-format}}" d
  if [ "$arg" = none ]; then printf none; return 0; fi
  case "$arg" in
    /*|.?/*) d="$arg" ;;                       # explicit path
    *)       d="$(dirname "$(resolve_defs)")/$arg.d" ;;  # NAME -> sibling
  esac
  [ -d "$d" ] || die "flavor dir not found: $d"
  printf '%s' "$d"
}

DEFS_ARG=""; FLAVOR_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --defs)   DEFS_ARG="${2:?--defs needs a DIR}"; shift 2 ;;
    --flavor) FLAVOR_ARG="${2:?--flavor needs DIR|NAME|none}"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

DEFS="${DEFS_ARG:-$(resolve_defs)}"
FLAVOR="$(resolve_flavor "$FLAVOR_ARG")"

scratch="${REPART_SCRATCH:-/var/tmp}"
mkdir -p "$scratch"
COMPOSED="$(mktemp -d "$scratch/compose.XXXXXX")"
cp -r "$DEFS"/. "$COMPOSED"/
if [ "$FLAVOR" != none ]; then
  cp -r "$FLAVOR"/. "$COMPOSED"/          # same-named files replace wholesale
fi
ls "$COMPOSED"/*.conf >/dev/null 2>&1 || { rm -rf "$COMPOSED"; die "composed defs have no *.conf (defs=$DEFS flavor=$FLAVOR)"; }

# @SWAP@ default (REPART_SWAP, 4G); explicit REPART_SED prepended so it wins
# (sed consumes matches: first expression to match wins).
export REPART_SED="${REPART_SED:+$REPART_SED;}s|@SWAP@|${REPART_SWAP:-4G}|g"

STAMPED="$(REPART_SCRATCH="$scratch" "$(stamp_bin)" "$COMPOSED")"
FINAL="$STAMPED/$(basename "$COMPOSED")"
rm -rf "$COMPOSED"                        # contract: only the stamped tree remains

note "defs: $DEFS + flavor: $FLAVOR"
printf '%s\n' "$FINAL"
