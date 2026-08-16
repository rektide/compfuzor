#!/bin/bash
# stamp.sh — copy file/dir(s) to a scratch tree and stamp @DATE@ tokens in them.
#
# WHY: dated-slot repart profiles (and mkosi config trees) carry a @DATE@
# token because repart has no date specifier. The token must be substituted
# at RUN time, never baked at render time (a rendered config would go stale),
# and the copy must NOT land in /tmp (tmpfs — copying trees into RAM will
# murder a constrained box).
#
# Part of the repart kit (files/repart/) — shared by pivot-bdr.srv.pb,
# mkosi.src.pb, installable standalone via repart-kit.opt.pb, and burned into
# disk images via mkosi.extra so spawned instances can stamp their own slots.
#
# USAGE
#   stamp.sh <src> [<src>...]      # copy each (basename preserved) + stamp
#   → echoes the scratch dir holding the stamped copies (caller rm -rf's it)
#
#   Multiple sources with the same basename: later wins (mkosi.conf from two
#   dirs would collide — callers keep them distinct).
#
# ENV
#   REPART_DATE    stamp (default: today, YYYYMMDD; validated digits-only)
#   REPART_TOKEN   token to replace (default: @DATE@)
#   REPART_SCRATCH scratch base (default: /var/tmp — on-disk, NOT tmpfs)
#
# Host deps: coreutils, sed, grep. No compfuzor assumptions.

set -euo pipefail

die()  { printf 'stamp: error: %s\n' "$*" >&2; exit 1; }
note() { printf 'stamp: %s\n' "$*" >&2; }

[ $# -ge 1 ] || { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

DATE="${REPART_DATE:-$(date +%Y%m%d)}"
TOKEN="${REPART_TOKEN:-@DATE@}"
SCRATCH="${REPART_SCRATCH:-/var/tmp}"

case "$DATE" in '' | *[!0-9]*) die "bad REPART_DATE '$DATE' (want YYYYMMDD)" ;; esac

for src in "$@"; do
  [ -e "$src" ] || die "source not found: $src"
done

mkdir -p "$SCRATCH"
DEST="$(mktemp -d "$SCRATCH/stamp.XXXXXX")"

for src in "$@"; do
  cp -r "$src" "$DEST/$(basename "$src")"
done

# stamp only files that carry the token (grep -lI skips binaries)
hit="$(grep -rl "$TOKEN" "$DEST" 2>/dev/null || true)"
if [ -n "$hit" ]; then
  # shellcheck disable=SC2086
  printf '%s\n' "$hit" | xargs sed -i "s|$TOKEN|$DATE|g"
fi

printf '%s\n' "$DEST"
note "stamped $DATE into $(echo "$hit" | wc -l) file(s) under $DEST"
