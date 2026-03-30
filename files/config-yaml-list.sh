#!/usr/bin/env bash

# header for config.sh binary

# versioning script's output files to paths with $TIMESTAMP is appreciated & good
export TIMESTAMP="$(date +%y.%m.%d-%T)"
# default a DIR
[ -z "$DIR" ] && export DIR="{{DIR}}"
# source envs, using envdefault for shell-local defaults when available
[ -n "$ENV_BYPASS" ] || [ ! -f "$DIR/env.export" ] || { command -v envdefault >/dev/null 2>&1 && source "$(command -v envdefault)" "$DIR/env.export" >/dev/null || source "$DIR/env.export"; }
# push current shell options onto stack for later restoration
_BIN_SETO_STATE+=("$(set +o)")
(( ${V:-0} > 2 )) && set -x
set -euo pipefail

# config.sh - Assemble drop-in YAML fragments into a single config
#
# Gathers all *.yaml from ${CONFIG_KEY}/ and concatenates as a YAML list.
# Disabled items are excluded (they live in ${CONFIG_KEY}-disabled/).
#
# ENV:
#   CONFIG_KEY     - drop-in directory name under etc/ (required)
#   CONFIG_OUTPUT  - output filename (default: ${CONFIG_KEY}.yaml)

shopt -s nullglob

dir="{{DIR}}"
key="${CONFIG_KEY:?CONFIG_KEY is required}"
output="${CONFIG_OUTPUT:-${key}.yaml}"
active=(${dir}/etc/${key}/*.yaml)

if [ ${#active[@]} -eq 0 ]; then
  echo "no ${key} configs found" >&2
  exit 0
fi

tmp=$(mktemp)
trap "rm -f $tmp" EXIT

for f in "${active[@]}"; do
  cat "$f"
  echo
done > "$tmp"

if [ -f "${dir}/etc/${output}" ] && cmp -s "$tmp" "${dir}/etc/${output}"; then
  echo "${key}: no changes"
  exit 0
fi

mv "$tmp" "${dir}/etc/${output}"
echo "${key}: assembled ${#active[@]} fragments -> etc/${output}"

# restore saved shell options by popping stack
(( ${#_BIN_SETO_STATE[@]} )) && { __saved="${_BIN_SETO_STATE[-1]}"; _BIN_SETO_STATE=("${_BIN_SETO_STATE[@]:0:${#_BIN_SETO_STATE[@]}-1}"); } || __saved=""
[ -n "${__saved:-}" ] && eval "$__saved"
unset __saved
