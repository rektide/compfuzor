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
name="$dirname"
for suffix in -git -main; do
  name="${name%$suffix}"
done
mcp_file="$src_dir/etc/mcp.json"

if [ ! -f "$mcp_file" ]; then
  echo "error: $mcp_file not found" >&2
  exit 1
fi

# Filter command args that reference empty/undefined env vars
filter_empty_args() {
  jq --argjson env "$(jq -n 'env')" '
    if .command then
      .command |= map(
        select(
          # Keep args where all ${VAR} references have non-empty env values
          [match("\\$\\{([A-Za-z_][A-Za-z0-9_]*)\\}"; "g").captures[0].string] |
          all(. as $var | $env[$var] // "" | length > 0)
        )
      ) |
      if .command == [] then del(.command) else . end
    else .
    end
  '
}

# Simplify --flag=true to --flag
simplify_flags() {
  jq '
    if .command then
      .command |= map(sub("=true$"; ""))
    else .
    end
  '
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

# Wrap in configured format
wrap_mcp() {
  local name="$1"
  local wrapper="${MCP_WRAPPER:-mcp}"
  jq --tab --arg name "$name" --arg wrapper "$wrapper" '{($wrapper): {($name): (. | .enabled = true)}}'
}

# Main
(
  (( V > 98 )) && set -x
  [ -f "$src_dir/env.export" ] && source "$src_dir/env.export"

  target_dir="${MCP_TARGET:-$self_dir/etc/mcp}"
  target="$target_dir/$name.json"
  mkdir -p "$target_dir"

  envsubst < "$mcp_file" | \
    filter_empty_args | \
    simplify_flags | \
    command_arg_splitter | \
    wrap_mcp "$name" > "$target"

  echo "installed: $target"
)

[ -f "$self_dir/bin/config.sh" ] && (cd "$self_dir" && ./bin/config.sh)
