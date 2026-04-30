: "${KERNEL_MODULES_JSON:?KERNEL_MODULES_JSON is required}"

"$DIR/bin/build-kernel.sh"

# Install-time responsibilities only:
# - materialize /etc/modules-load.d and /etc/modprobe.d or /etc/kernel/cmdline
# - do not modprobe or push live param values (that is apply-kernel.sh)
sudo mkdir -p /etc/modules-load.d /etc/modprobe.d
sudo ln -sf "$DIR/etc/kernel.modules-load.conf" "/etc/modules-load.d/{{ NAME }}.conf"

# Determine which persistence mechanism we need.
# If any requested module is built in, modprobe options will not apply for that
# module at boot; in that case we use kernel cmdline persistence.
_cf_kernel_mode=""
while IFS= read -r _cf_module; do
  [ -n "$_cf_module" ] || continue
  _cf_detected="$($DIR/bin/detect-builtin.sh "$_cf_module" || true)"
  if [ "$_cf_detected" = "builtin" ]; then
    _cf_kernel_mode="builtin"
    break
  fi
  if [ "$_cf_detected" = "module" ] && [ -z "$_cf_kernel_mode" ]; then
    _cf_kernel_mode="module"
  fi
done < <(jq -r 'to_entries | sort_by(.key) | .[].key' "$KERNEL_MODULES_JSON")

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
