: "${KERNEL_MODULES_JSON:?KERNEL_MODULES_JSON is required}"

# Apply-time responsibilities only:
# - best-effort load module now (when it is a loadable module)
# - write live values into /sys/module/*/parameters/* when writable
# Install-time persistence is handled by install-kernel.sh.
jq -cr 'to_entries | sort_by(.key) | .[]' "$KERNEL_MODULES_JSON" |
while IFS= read -r _cf_module_entry; do
  _cf_module="$(jq -r '.key' <<<"$_cf_module_entry")"
  _cf_kind="$($DIR/bin/detect-builtin.sh "$_cf_module" || true)"

  if [ "$_cf_kind" = "module" ]; then
    if jq -e '.value.load != false' <<<"$_cf_module_entry" >/dev/null 2>&1; then
      sudo modprobe "$_cf_module" >/dev/null 2>&1 || true
    fi
  fi

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
