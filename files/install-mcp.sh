#!/usr/bin/env bash
# install-mcp.sh - Install an MCP server configuration
#
# This script:
# 1. Sources environment from source package's env.export
# 2. Runs envsubst to substitute ${VAR} placeholders in mcp.json
# 3. Filters out command array elements that reference empty/undefined variables
# 4. Optionally splits command array into command+args (for amp format)
# 5. Wraps result in configured format and writes to target
#
# Environment variables (from env.export):
#   MCP_TARGET  - Directory to write mcp config (default: $DIR/etc/mcp)
#   MCP_WRAPPER - JSON wrapper path: "mcp" or "amp.mcpServers" (default: mcp)
#   MCP_COMMAND_ARGS - If set, split command[0] into command, rest into args
#
# Usage: install-mcp.sh [source_dir]

self_dir="{{DIR}}"
source $self_dir/env.export

src_dir="${1:-$(pwd)}"
dirname=$(basename "$src_dir")
mcp_file="$src_dir/etc/mcp.json"

if [ ! -f "$mcp_file" ]; then
  echo "error: $mcp_file not found" >&2
  exit 1
fi

filter_empty_args() {
  local json
  json=$(cat)

  local command_array
  command_array=$(echo "$json" | jq -c '.command // empty')

  if [ -z "$command_array" ] || [ "$command_array" = "null" ]; then
    echo "$json"
    return
  fi

  local filtered_cmd
  filtered_cmd=$(echo "$command_array" | jq -r '.[]' | while read -r arg; do
    local has_empty_var=0
    local var_patterns
    var_patterns=$(echo "$arg" | grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' 2>/dev/null || true)

    if [ -n "$var_patterns" ]; then
      while IFS= read -r pattern; do
        local var_name="${pattern#\${}"
        var_name="${var_name%\}}"

        local var_value
        if [ -n "${ZSH_VERSION:-}" ]; then
          var_value="${(P)var_name:-}"
        else
          var_value="${!var_name:-}"
        fi

        if [ -z "$var_value" ]; then
          has_empty_var=1
          break
        fi
      done <<< "$var_patterns"
    fi

    if [ "$has_empty_var" -eq 0 ]; then
      echo "$arg"
    fi
  done | jq -R -s -c 'split("\n") | map(select(length > 0))')

  if [ "$filtered_cmd" = "[]" ]; then
    echo "$json" | jq 'del(.command)'
  else
    echo "$json" | jq --argjson cmd "$filtered_cmd" '.command = $cmd'
  fi
}

# Split command array into command + args (for amp format)
command_arg_splitter() {
  local json
  json=$(cat)

  # Pass through if MCP_COMMAND_ARGS not set
  if [ -z "${MCP_COMMAND_ARGS:-}" ]; then
    echo "$json"
    return
  fi

  local command_array
  command_array=$(echo "$json" | jq -c '.command // empty')

  if [ -z "$command_array" ] || [ "$command_array" = "null" ]; then
    echo "$json"
    return
  fi

  # Split: first element -> command (string), rest -> args (array)
  echo "$json" | jq '
    if .command then
      .command as $cmd |
      del(.command) |
      .command = $cmd[0] |
      if ($cmd | length) > 1 then .args = $cmd[1:] else . end
    else .
    end
  '
}

# Wrap in configured format (mcp or amp.mcpServers)
wrap_mcp() {
  local name="$1"
  local wrapper="${MCP_WRAPPER:-mcp}"

  if [ "$wrapper" = "amp.mcpServers" ]; then
    jq --tab --arg name "$name" '{"amp.mcpServers": {($name): (. | .enabled = true)}}'
  else
    jq --tab --arg name "$name" '{"mcp": {($name): (. | .enabled = true)}}'
  fi
}

# Main
(
  (( V > 98 )) && set -x
  [ -f "$src_dir/env.export" ] && source "$src_dir/env.export"

  target_dir="${MCP_TARGET:-$self_dir/etc/mcp}"
  target="$target_dir/$dirname.json"
  mkdir -p "$target_dir"

  envsubst < "$mcp_file" | \
    filter_empty_args | \
    command_arg_splitter | \
    wrap_mcp "$dirname" > "$target"

  echo "installed: $target"
)

[ -f "$self_dir/bin/config.sh" ] && (cd "$self_dir" && ./bin/config.sh)
