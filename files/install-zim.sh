#!/usr/bin/env bash
# Complete ordinary Zim installation for a selected declared context.

set -euo pipefail

invoked=$(basename "$0")
script=$(readlink -f -- "$0")
root=$(dirname "$(dirname "$script")")
exec "$root/bin/zim/install.mjs" install --invoked-as "$invoked" "$@"
