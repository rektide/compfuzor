: "${KERNEL_SYSFS_JSON:?KERNEL_SYSFS_JSON is required}"

: > "$DIR/etc/kernel.tmpfiles.conf"

jq -cr 'to_entries | sort_by(.key) | .[]' "$KERNEL_SYSFS_JSON" |
while IFS= read -r _cf_entry; do
  _cf_pattern="$(jq -r '.key' <<<"$_cf_entry")"
  _cf_value="$(jq -r '.value|tostring' <<<"$_cf_entry")"
  _cf_matches=()

  while IFS= read -r _cf_match; do
    _cf_matches+=("$_cf_match")
  done < <(compgen -G "$_cf_pattern")

  if [ ${#_cf_matches[@]} -eq 0 ]; then
    printf 'No matches for KERNEL_SYSFS pattern: %s\n' "$_cf_pattern" >&2
    exit 1
  fi

  for _cf_path in "${_cf_matches[@]}"; do
    printf 'w %s - - - - %s\n' "$_cf_path" "$_cf_value" >> "$DIR/etc/kernel.tmpfiles.conf"
  done
done
