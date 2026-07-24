: "${KERNEL_MODULES_JSON:?KERNEL_MODULES_JSON is required}"

_cf_cmdline_file="/etc/kernel/cmdline"

# Ensure cmdline file exists so we can perform read-modify-write updates.
sudo mkdir -p /etc/kernel
sudo touch "$_cf_cmdline_file"

_cf_existing="$(sudo cat "$_cf_cmdline_file")"
_cf_updated="$_cf_existing"

# Convert each module param into a cmdline token shape: module.param=value.
# If token already exists, replace it in-place. Otherwise append it.
while IFS= read -r _cf_line; do
  [ -n "$_cf_line" ] || continue

  _cf_key="${_cf_line%%=*}"
  # Collapse to a single copy: strip EVERY existing occurrence of this key so
  # stale duplicates can't survive a re-run, then append the desired value once.
  _cf_updated="$(printf '%s\n' "$_cf_updated" | sed -E "s#(^|[[:space:]])${_cf_key}=[^[:space:]]*##g" | tr -s ' ' | sed -E 's/^ //; s/ $//')"
  _cf_updated="${_cf_updated:+${_cf_updated} }${_cf_line}"
done < <(
  jq -r '
    to_entries
    | sort_by(.key)
    | map(
        .key as $module
        | (.value.params // {} | to_entries | sort_by(.key))
        | map("\($module).\(.key)=\(.value|tostring)")
      )
    | .[]
    | .[]
  ' "$KERNEL_MODULES_JSON"
)

# Normalize whitespace to keep file deterministic and easy to diff.
_cf_updated="$(printf '%s\n' "$_cf_updated" | tr -s '[:space:]' ' ' | sed -E 's/^ //; s/ $//')"

printf '%s\n' "$_cf_updated" | sudo tee "$_cf_cmdline_file" >/dev/null
