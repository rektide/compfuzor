#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: pkg-check.sh <playbook.pb> [playbook.pb ...]" >&2
    exit 1
fi

_yq_raw_flag=()
if yq --version 2>&1 | grep -q '^yq [0-9]'; then
    _yq_raw_flag=(-r)
fi

_status_of() {
    local version
    version=$(dpkg-query -W -f '${Version}' "$1" 2>/dev/null) || true
    if [[ -n "$version" ]]; then
        echo "$version"
    else
        echo "<none>"
    fi
}

for pb in "$@"; do
    pkgs=$(yq "${_yq_raw_flag[@]}" '.[].vars.PKGS[]' "$pb" 2>/dev/null) || true
    [[ -z "$pkgs" ]] && continue

    echo "# $(basename "$pb")"
    while IFS= read -r pkg; do
        printf '%-40s %s\n' "$pkg" "$(_status_of "$pkg")"
    done <<< "$pkgs"
    echo
done
