#!/usr/bin/env bash
# install-zim.sh - explicitly promote contributor fragments to the canonical donor.
#
# Contributors render module fragments under etc/zim/<channel>/{active,disabled}.
# This script symlinks them into the host's channel-named remote targets so the
# generic block-in-file config assembler picks them up in sorted filename order.
# This is an admin operation affecting the shared donor roster. It never builds
# a consumer's Zim cache and is not composed into install-user.sh.
#
# Usage: install-zim.sh [source_dir]   # source_dir defaults to $PWD

set -e

self_dir="{{DIR}}"

# The env-export header only defaults $DIR when unset. Invoked from a
# contributor's install-user-zimfw.sh, DIR still points at the contributor and
# leaks into config-remote.ts/config.sh, which then resolve the contributor's
# config.spec.json instead of the host's. This script is always host-scoped:
# force DIR to the host deployment.
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
