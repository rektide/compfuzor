#!/usr/bin/env bash

# header for disable.sh binary

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

# disable.sh - Disable config drop-ins by moving them to the disabled directory
#
# Accepts glob patterns. Matching files are moved from etc/${CONFIG_KEY}/
# to etc/${CONFIG_KEY}-disabled/ and config.sh is re-run.
#
# ENV:
#   CONFIG_KEY - drop-in directory name under etc/ (required)

shopt -s nullglob

dir="{{DIR}}"
key="${CONFIG_KEY:?CONFIG_KEY is required}"
mkdir -p "${dir}/etc/${key}-disabled"

files=()
for pattern in "$@"; do
  if [ -f "$pattern" ]; then
    files+=("$pattern")
    continue
  fi

  orig_pattern="$pattern"
  start_count=${#files[@]}

  pattern="${pattern%.yaml}"
  for yaml_file in ${dir}/etc/${key}/*.yaml; do
    filename=$(basename "$yaml_file")
    [[ "$filename" =~ $pattern ]] && files+=("$yaml_file") && continue
    [[ "${filename%.yaml}" =~ $pattern ]] && files+=("$yaml_file")
  done

  [ $start_count -eq ${#files[@]} ] && echo "no match: $orig_pattern"
done

for yaml_file in "${files[@]}"; do
  filename=$(basename "$yaml_file")
  target="${dir}/etc/${key}-disabled/$filename"

  if [ -f "$target" ]; then
    echo "skipped (already disabled): $filename"
    continue
  fi

  mv "$yaml_file" "$target"
  echo "disabled: $filename"
done

[ -f "${dir}/bin/config.sh" ] && (cd "$dir" && ./bin/config.sh)

# restore saved shell options by popping stack
(( ${#_BIN_SETO_STATE[@]} )) && { __saved="${_BIN_SETO_STATE[-1]}"; _BIN_SETO_STATE=("${_BIN_SETO_STATE[@]:0:${#_BIN_SETO_STATE[@]}-1}"); } || __saved=""
[ -n "${__saved:-}" ] && eval "$__saved"
unset __saved
