#!/usr/bin/env bash

# header for disable.sh binary

# versioning script's output files to paths with $TIMESTAMP is appreciated & good
export TIMESTAMP="$(date +%y.%m.%d-%T)"
# V>98 triggers set -x. but save set -x state to restore later, in case being sourced.
(( V > 98 )) && case "$-" in *x*) _BIN_SETX_STATE+=(1) ;; *) _BIN_SETX_STATE+=(0) ;; esac && set -x
set -e



# disable.sh - Disable MCP servers by moving them to mcp-disabled directory
#
# This script accepts glob patterns and moves matching MCP configs to the disabled directory,
# creating a disabled wrapper that sets enabled=false for the MCP.
#
# Usage: disable.sh [pattern1 pattern2 ...]

shopt -s nullglob

dir="{{DIR}}"
mkdir -p ${dir}/etc/mcp-disabled

files=()
for pattern in "$@"; do
  if [ -f "$pattern" ]; then
    files+=("$pattern")
    continue
  fi

  orig_pattern="$pattern"
  start_count=${{ '{#' }}files[@]}

  pattern="${pattern%.json}"
  for json_file in ${dir}/etc/mcp/*.json; do
    filename=$(basename "$json_file")
    [[ "$filename" =~ $pattern ]] && files+=("$json_file") && continue
    [[ "${filename%.json}" =~ $pattern ]] && files+=("$json_file")
  done

  [ $start_count -eq ${{'{#'}}files[@]} ] && echo "no match: $orig_pattern"
done

for json_file in "${files[@]}"; do
  filename=$(basename "$json_file")
  target="${dir}/etc/mcp-disabled/$filename"

  if [ -f "$target" ]; then
    echo "skipped: $filename"
    continue
  fi

  mcp_key=$(jq -r '.mcp | keys[0]' "$json_file")
  echo "{\"mcp\":{\"$mcp_key\":{\"enabled\":false}}}" > "$target"
  echo "created: $filename"
done

[ -f "$dir/bin/config.sh" ] && (cd "$dir" && ./bin/config.sh)



# restore set -x/+x to what it was when we started, if we changed it
if (( V > 98 )); then
	(( ${_BIN_SETX_STATE[-1]} > 0 )) || set +x # restore
	_BIN_SETX_STATE=("${_BIN_SETX_STATE[@]:1}") # pop
fi
