#!/usr/bin/env bash
set -euo pipefail

_invoke=$(basename "$(readlink -f "$0" 2>/dev/null || echo "$0")")
_mode=check
[[ "$_invoke" == *install* ]] && _mode=install

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

if [[ $# -eq 0 ]]; then
    echo "usage: $_invoke <playbook.pb> [playbook.pb ...] [-- column-args...]" >&2
    exit 1
fi

pbs=()
column_args=()
saw_sep=false
for arg in "$@"; do
    if [[ "$arg" == "--" ]] && [[ "$saw_sep" == false ]]; then
        saw_sep=true
        continue
    fi
    if [[ "$saw_sep" == true ]]; then
        column_args+=("$arg")
    else
        pbs+=("$arg")
    fi
done

_missing=()

for pb in "${pbs[@]}"; do
    pkgs=$(yq "${_yq_raw_flag[@]}" '.[].vars.PKGS[]' "$pb" 2>/dev/null) || true
    [[ -z "$pkgs" ]] && continue

    echo "# $(basename "$pb")"
    {
        while IFS= read -r pkg; do
            version=$(_status_of "$pkg")
            if [[ "$_mode" == "install" && "$version" == "<none>" ]]; then
                _missing+=("$pkg")
            fi
            echo "$pkg"$'\t'"$version"
        done <<< "$pkgs"
    } | column -s $'\t' -t "${column_args[@]}"
    echo
done

if [[ "$_mode" == "install" && ${#_missing[@]} -gt 0 ]]; then
    echo "# installing ${#_missing[@]} missing package(s)"
    sudo aptitude install -y "${_missing[@]}"
fi
