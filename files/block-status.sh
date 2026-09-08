#!/usr/bin/env bash
# Compare one named block-in-file projection with its declared source.

set -euo pipefail

name=${1:?usage: block-status.sh NAME SOURCE DESTINATION}
source=${2:?usage: block-status.sh NAME SOURCE DESTINATION}
destination=${3:?usage: block-status.sh NAME SOURCE DESTINATION}
command=${CONFIG_BLOCK_IN_FILE:-block-in-file}

[ -f "$source" ] || { echo "drift: block source is missing: $source"; exit 1; }
candidate=$(mktemp)
trap 'rm -f "$candidate"' EXIT
if ! "$command" --read -n "$name" "$destination" > "$candidate"; then
  echo "drift: block $name is missing or unreadable in $destination"
  exit 1
fi
if cmp -s "$source" "$candidate"; then exit 0; fi
echo "drift: block $name in $destination differs from $source"
diff -u "$candidate" "$source" || true
exit 1
