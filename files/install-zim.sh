#!/usr/bin/env bash
# install-zim.sh - delegate contributor zim fragments to the host remote tool.
#
# Contributors render module fragments under etc/zim/<channel>/{active,disabled}.
# This script symlinks them into the host's channel-named remote targets so the
# generic block-in-file config assembler picks them up in sorted filename order. Symlinks (not
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
declare -A touched_channels
for channel_dir in "$src_dir"/etc/zim/*; do
  [ -d "$channel_dir" ] || continue
  channel="$(basename "$channel_dir")"
  touched_channels["$channel"]=1
  for f in "$channel_dir"/active/*.conf; do
    "$remote" link "$channel" "$f"
    count=$((count + 1))
  done
  for f in "$channel_dir"/disabled/*.conf; do
    name="$(basename "$f")"
    "$remote" link "$channel" "$f" "$name"
    "$remote" disable "$channel" "$name"
    count=$((count + 1))
  done
done

if [ -x "$self_dir/bin/zimfw-channel.sh" ]; then
  for channel in "${!touched_channels[@]}"; do
    "$self_dir/bin/zimfw-channel.sh" "$channel" install
  done
fi

echo "install-zim: delegated $count fragment(s)"
