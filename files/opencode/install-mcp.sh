#!/usr/bin/env bash
# install-mcp.sh - Install an MCP server configuration into opencode
#
# This script:
# 1. Sources environment from source package's env.export
# 2. Runs envsubst to substitute ${VAR} placeholders in mcp.json
# 3. Filters out command array elements that reference empty/undefined variables
# 4. Wraps result in opencode's mcp format and writes to target
#
# Usage: install-mcp.sh [source_dir]

opencode_dir="{{DIR}}"
src_dir="${1:-$(pwd)}"
dirname=$(basename "$src_dir")
mcp_file="$src_dir/etc/mcp.json"
target="$opencode_dir/etc/mcp/$dirname.json"

if [ ! -f "$mcp_file" ]; then
  echo "error: $mcp_file not found" >&2
  exit 1
fi

mkdir -p "$(dirname "$target")"

filter_empty_args() {
  local json
  json=$(cat)

  # Extract command array from JSON
  local command_array
  command_array=$(echo "$json" | jq -c '.command // empty')

  # If no command array exists, return unchanged
  if [ -z "$command_array" ] || [ "$command_array" = "null" ]; then
    echo "$json"
    return
  fi

  # Filter each command argument
  local filtered_cmd
  filtered_cmd=$(echo "$command_array" | jq -r '.[]' | while read -r arg; do
    # Check if arg contains any ${VAR} patterns
    local has_empty_var=0

    # Use grep to find all ${VAR} patterns in arg
    # -o: output only matched parts
    # -E: extended regex for ${VAR} pattern
    local var_patterns
    var_patterns=$(echo "$arg" | grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' 2>/dev/null || true)

    # Check each variable pattern
    if [ -n "$var_patterns" ]; then
      while IFS= read -r pattern; do
        # Extract variable name from ${VAR_NAME}
        local var_name="${pattern#\${}"  # Remove ${ prefix
        var_name="${var_name%\}}"         # Remove } suffix

        # Get variable value (shell-specific for indirect reference)
        local var_value
        if [ -n "${ZSH_VERSION:-}" ]; then
          var_value="${(P)var_name:-}"  # zsh indirect expansion
        else
          var_value="${!var_name:-}"     # bash indirect expansion
        fi

        # If any variable is empty, mark this arg for removal
        if [ -z "$var_value" ]; then
          has_empty_var=1
          break
        fi
      done <<< "$var_patterns"
    fi

    # Only keep the arg if no empty variables were found
    if [ "$has_empty_var" -eq 0 ]; then
      echo "$arg"
    fi
  done | jq -R -s -c 'split("\n") | map(select(length > 0))')

  # Update JSON with filtered command or remove command array if empty
  if [ "$filtered_cmd" = "[]" ]; then
    echo "$json" | jq 'del(.command)'
  else
    echo "$json" | jq --argjson cmd "$filtered_cmd" '.command = $cmd'
  fi
}

# Main pipeline: source env, substitute vars, filter empty args, wrap in mcp format
(
  (( V > 98 )) && set -x
  [ -f "$src_dir/env.export" ] && source "$src_dir/env.export"
  envsubst < "$mcp_file" | \
    filter_empty_args | \
    jq --tab --arg name "$dirname" '{"mcp": {($name): (. | .enabled = true)}}' > "$target"
)
[ -f "$opencode_dir/bin/config.sh" ] && (cd "$opencode_dir" && ./bin/config.sh)
