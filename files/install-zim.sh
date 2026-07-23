#!/usr/bin/env bash
# install-zim.sh - promote a contributor's zim fragments into the host target.
#
# Contributors render module fragments under etc/zim/ (and etc/zim-disabled/
# for enabled:false entries). This script symlinks them into the host's
# assembly directory (etc/zimfw/ by default) so the generic block-in-file
# config assembler picks them up in sorted filename order. Symlinks (not
# copies) keep the contributor as source-of-truth, so a re-rendered fragment
# updates the host automatically and status-config.sh --check detects drift.
#
# Environment (sourced from the host's env.export):
#   ZIM_TARGET          - host active dir    (default: $DIR/etc/zimfw)
#   ZIM_TARGET_DISABLED - host disabled dir  (default: ${ZIM_TARGET}-disabled)
#
# Usage: install-zim.sh [source_dir]   # source_dir defaults to $PWD

set -e

self_dir="{{DIR}}"
[ -f "$self_dir/env.export" ] && source "$self_dir/env.export"

src_dir="${1:-$(pwd)}"
active="${ZIM_TARGET:-$self_dir/etc/zimfw}"
disabled="${ZIM_TARGET_DISABLED:-${active}-disabled}"

mkdir -p "$active" "$disabled"

count=0
shopt -s nullglob
for f in "$src_dir"/etc/zim/*.conf; do
  ln -sfv "$f" "$active/$(basename "$f")"
  count=$((count + 1))
done
for f in "$src_dir"/etc/zim-disabled/*.conf; do
  ln -sfv "$f" "$disabled/$(basename "$f")"
  count=$((count + 1))
done

echo "install-zim: promoted $count fragment(s) -> $active"
