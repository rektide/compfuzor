: "${KERNEL_MODULES_JSON:?KERNEL_MODULES_JSON is required}"

# Build /etc/modules-load.d payload from modules with load != false.
jq -r '
  to_entries
  | sort_by(.key)
  | map(select(.value.load != false) | .key)
  | .[]
' "$KERNEL_MODULES_JSON" > "$DIR/etc/kernel.modules-load.conf"

# Build /etc/modprobe.d payload from per-module params.
jq -r '
  to_entries
  | sort_by(.key)
  | map(
      .key as $module
      | (.value.params // {} | to_entries | sort_by(.key)) as $params
      | select(($params | length) > 0)
      | "options \($module) " + ($params | map("\(.key)=\(.value|tostring)") | join(" "))
    )
  | .[]
' "$KERNEL_MODULES_JSON" > "$DIR/etc/kernel.modprobe.conf"
