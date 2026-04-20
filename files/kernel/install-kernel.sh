: "${KERNEL_MODULES_JSON:?KERNEL_MODULES_JSON is required}"

"$DIR/bin/build-kernel.sh"

sudo mkdir -p /etc/modules-load.d /etc/modprobe.d
sudo ln -sf "$DIR/etc/kernel.modules-load.conf" "/etc/modules-load.d/{{ NAME }}.conf"

if [ -s "$DIR/etc/kernel.modprobe.conf" ]; then
  sudo ln -sf "$DIR/etc/kernel.modprobe.conf" "/etc/modprobe.d/{{ NAME }}.conf"
else
  sudo rm -f "/etc/modprobe.d/{{ NAME }}.conf"
fi

# Ensure modules intended for boot-time load are also available now.
jq -r '
  to_entries
  | sort_by(.key)
  | map(select(.value.load != false) | .key)
  | .[]
' "$KERNEL_MODULES_JSON" |
while IFS= read -r _cf_module; do
  [ -n "$_cf_module" ] || continue
  sudo modprobe "$_cf_module" >/dev/null 2>&1 || true
done

# Push param values immediately for modules that are already loaded.
jq -cr 'to_entries | sort_by(.key) | .[]' "$KERNEL_MODULES_JSON" |
while IFS= read -r _cf_module_entry; do
  _cf_module="$(jq -r '.key' <<<"$_cf_module_entry")"

  jq -cr '.value.params // {} | to_entries | sort_by(.key) | .[]' <<<"$_cf_module_entry" |
  while IFS= read -r _cf_param_entry; do
    _cf_param="$(jq -r '.key' <<<"$_cf_param_entry")"
    _cf_value="$(jq -r '.value|tostring' <<<"$_cf_param_entry")"
    _cf_path="/sys/module/${_cf_module}/parameters/${_cf_param}"

    if [ -w "$_cf_path" ]; then
      printf '%s\n' "$_cf_value" | sudo tee "$_cf_path" >/dev/null
    fi
  done
done
