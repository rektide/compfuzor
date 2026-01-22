#!/usr/bin/env bash

# header for install-mcp.sh binary

# versioning script's output files to paths with $TIMESTAMP is appreciated & good
export TIMESTAMP="$(date +%y.%m.%d-%T)"
# default a DIR
[ -z "$DIR" ] && export DIR="{{DIR}}"
# source envs, using envdefaults if available to not override any variables the shell already has set
[ -n "$ENV_BYPASS" ] || [ ! -f "$DIR/env.export" ] || source <(command -v envdefault >/dev/null && envdefault "$DIR/env.export" || cat "$DIR/env.export")
# V>98 triggers set -x. but save set -x state to restore later, in case being sourced.
(( V > 98 )) && case "$-" in *x*) _BIN_SETX_STATE+=(1) ;; *) _BIN_SETX_STATE+=(0) ;; esac && set -x
set -e

# config-mcp.sh - Combine all MCP server configurations into opencode's settings
#
# This script:
# 1. Gathers all MCP JSON configs from ${MCP_TARGET}/mcp/
# 2. Merges them with base.json and disabled configs
# 3. Writes the combined settings to opencode.json
#
# Usage: config-mcp.sh

shopt -s nullglob

MCP_TARGET="${MCP_TARGET:-{{ETC}}/mcp}"
DIR="{{DIR}}"

configs=(${DIR}/etc/mcp/*.json)
disabled=(${DIR}/etc/mcp-disabled/*.json)

if [ ${{ '{#' }}configs[@]} -eq 0 ]; then
  echo "no mcp configs found" >&2
  exit 0
fi

base_files=()
[ -f "${DIR}/etc/base.json" ] && base_files=("${DIR}/etc/base.json")

jq -s 'reduce .[] as $item ({}; . * $item)' "${base_files[@]}" "${configs[@]}" "${disabled[@]}" > "${DIR}/etc/${MCP_CONF}"
