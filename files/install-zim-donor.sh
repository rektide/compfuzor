#!/usr/bin/env bash
# Explicitly promote contributor fragments to the canonical donor.

set -e

self_dir="{{DIR}}"
export DIR="$self_dir"
src_dir="${1:-$(pwd)}"
remote="$self_dir/bin/config-remote.ts"

count=0
shopt -s nullglob
for channel_dir in "$src_dir"/etc/zim/*; do
  [ -d "$channel_dir" ] || continue
  channel="$(basename "$channel_dir")"
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

echo "install-zim-donor: promoted $count fragment(s) to the canonical donor"
