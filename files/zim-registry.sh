#!/usr/bin/env bash
# Apply or inspect the runtime-selected canonical Zim host registry link.

set -euo pipefail

action=${1:?usage: zim-registry.sh apply|status}
case "$action" in apply|status) ;; *) echo "unknown registry action: $action" >&2; exit 2 ;; esac

self_dir="{{DIR}}"
canonical="{{ETC}}/zimrc"
registry="${ZIM_CONFIG_LINK:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh/zimfw.conf}"
manager="$self_dir/bin/links.ts"
[ -x "$manager" ] || { echo "missing LINKS manager: $manager" >&2; exit 2; }

manifest=$(mktemp)
trap 'rm -f "$manifest"' EXIT
jq -n \
  --arg dir "$self_dir" \
  --arg src "$canonical" \
  --arg dest "$registry" \
  '{version: 1, deployment: {dir: $dir}, links: [{id: "zim-host-registry", scope: "user", src: $src, dest: $dest, policy: "replace", state: "present"}]}' \
  > "$manifest"

if [ "$action" = apply ]; then
  "$manager" apply --scope user --sudo never "$manifest"
else
  "$manager" status --scope user "$manifest"
fi
