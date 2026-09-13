#!/usr/bin/env bash
# Import one producer into the selected declared Zim context.

set -euo pipefail

script=$(readlink -f -- "$0")
root=$(dirname "$(dirname "$script")")
exec "$root/bin/zim/install.mjs" import "$@"
