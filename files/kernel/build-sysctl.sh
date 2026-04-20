: "${KERNEL_SYSCTL_JSON:?KERNEL_SYSCTL_JSON is required}"

jq -r '
  to_entries
  | sort_by(.key)
  | map("\(.key) = \(.value|tostring)")
  | .[]
' "$KERNEL_SYSCTL_JSON" > "$DIR/etc/kernel.sysctl.conf"
