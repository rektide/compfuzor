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
  if printf '%s\n' "$_cf_updated" | grep -Eq "(^|[[:space:]])${_cf_key}="; then
    _cf_updated="$(printf '%s\n' "$_cf_updated" | sed -E "s#(^|[[:space:]])${_cf_key}=[^[:space:]]*#\\1${_cf_line}#")"
  else
    _cf_updated="${_cf_updated} ${_cf_line}"
  fi
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
