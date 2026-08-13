#!/usr/bin/env bash
# install-zim.sh - delegate contributor zim fragments to the host remote tool.
#
# Contributors render module fragments under etc/zim/ (and etc/zim-disabled/
# for enabled:false entries). This script symlinks them into the host's
# assembly directory (etc/zimfw/ by default) so the generic block-in-file
# config assembler picks them up in sorted filename order. Symlinks (not
# copies) keep the contributor as source-of-truth, so a re-rendered fragment
# updates the host automatically and status-config-zim.sh detects drift.
#
# Usage: install-zim.sh [source_dir]   # source_dir defaults to $PWD

set -e

self_dir="{{DIR}}"

src_dir="${1:-$(pwd)}"
remote="$self_dir/bin/config-remote.ts"

count=0
shopt -s nullglob
for f in "$src_dir"/etc/zim/*.conf; do
  "$remote" link zimfw.conf.d "$f"
  count=$((count + 1))
done
for f in "$src_dir"/etc/zim-disabled/*.conf; do
  name="$(basename "$f")"
  "$remote" link zimfw.conf.d "$f" "$name"
  "$remote" disable zimfw.conf.d "$name"
  count=$((count + 1))
done

echo "install-zim: delegated $count fragment(s) to zimfw.conf.d"
