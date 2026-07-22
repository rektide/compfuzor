: "${KERNEL_MODULES_JSON:?KERNEL_MODULES_JSON is required}"

"$DIR/bin/build-kernel.sh"

# Install-time responsibilities only:
# - materialize /etc/modules-load.d and /etc/modprobe.d or /etc/kernel/cmdline
# - do not modprobe or push live param values (that is apply-kernel.sh)
sudo mkdir -p /etc/modules-load.d /etc/modprobe.d
sudo ln -sf "$DIR/etc/kernel.modules-load.conf" "/etc/modules-load.d/{{ NAME }}.conf"

# Determine which persistence mechanism we need.
# - If any requested module is built in, modprobe options will not apply for that
#   module at boot; in that case we use kernel cmdline persistence.
# - If any requested module has force_cmdline: true, the playbook author has
#   declared that modprobe.d timing is wrong for this module (e.g. it loads
#   from initramfs before /etc/modprobe.d is parsed, or its params are read at
#   kernel init). Force the cmdline path regardless of builtin detection.
_cf_kernel_mode=""
while IFS= read -r _cf_entry; do
  _cf_module="$(jq -r '.key' <<<"$_cf_entry")"
  _cf_force="$(jq -r '.value.force_cmdline // false' <<<"$_cf_entry")"
  if [ "$_cf_force" = "true" ]; then
    _cf_kernel_mode="builtin"
    break
  fi
  _cf_detected="$($DIR/bin/detect-builtin.sh "$_cf_module" || true)"
  if [ "$_cf_detected" = "builtin" ]; then
    _cf_kernel_mode="builtin"
    break
  fi
  if [ "$_cf_detected" = "module" ] && [ -z "$_cf_kernel_mode" ]; then
    _cf_kernel_mode="module"
  fi
done < <(jq -c 'to_entries | sort_by(.key) | .[]' "$KERNEL_MODULES_JSON")

if [ "$_cf_kernel_mode" = "builtin" ]; then
  printf 'kernel install path: builtin, using /etc/kernel/cmdline\n'
  # Keep modprobe drop-in absent to avoid misleading config drift.
  sudo rm -f "/etc/modprobe.d/{{ NAME }}.conf"
  # Convert options lines into kernel cmdline tokens (<module>.<param>=value).
  "$DIR/bin/install-kernel-cmdline.sh"
else
  printf 'kernel install path: module, using /etc/modprobe.d\n'
  if [ -s "$DIR/etc/kernel.modprobe.conf" ]; then
    sudo ln -sf "$DIR/etc/kernel.modprobe.conf" "/etc/modprobe.d/{{ NAME }}.conf"
  else
    sudo rm -f "/etc/modprobe.d/{{ NAME }}.conf"
  fi
fi
