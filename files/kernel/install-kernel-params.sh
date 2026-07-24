: "${KERNEL_PARAMS_JSON:?KERNEL_PARAMS_JSON is required}"

# Idempotent writer for raw kernel cmdline tokens (the things that don't fit
# the <module>.<param>=<value> shape install-kernel-cmdline.sh handles).
#
# KERNEL_PARAMS_JSON is a JSON array of strings, e.g.:
#   ["memmap=256K$0x100000000", "nospectre_v2", "rootflags=subvol=/root"]
#
# For each token:
#   - key=value form: replace any existing <key>=* in-place by key prefix
#   - flag form (no =): add once if absent
# Result is normalized to single spaces and written to /etc/kernel/cmdline,
# which kernel-install propagates to BLS entries on next kernel-install hook.

_cf_cmdline_file="/etc/kernel/cmdline"

sudo mkdir -p /etc/kernel
sudo touch "$_cf_cmdline_file"

_cf_existing="$(sudo cat "$_cf_cmdline_file")"
_cf_updated="$_cf_existing"

while IFS= read -r _cf_line; do
  [ -n "$_cf_line" ] || continue

  case "$_cf_line" in
    *=*)
      # key=value form: collapse -- strip every existing occurrence of this key
      # so stale duplicates can't survive, then append the desired value once.
      _cf_key="${_cf_line%%=*}"
      _cf_updated="$(printf '%s\n' "$_cf_updated" | sed -E "s#(^|[[:space:]])${_cf_key}=[^[:space:]]*##g" | tr -s ' ' | sed -E 's/^ //; s/ $//')"
      ;;
    *)
      # flag form: collapse -- drop every existing copy of this exact flag, then
      # append once.
      _cf_updated="$(printf '%s\n' "$_cf_updated" | tr ' ' '\n' | grep -vx -- "$_cf_line" | paste -sd ' ' -)"
      ;;
  esac
  _cf_updated="${_cf_updated:+${_cf_updated} }${_cf_line}"
done < <(jq -r '.[]' "$KERNEL_PARAMS_JSON")

_cf_updated="$(printf '%s\n' "$_cf_updated" | tr -s '[:space:]' ' ' | sed -E 's/^ //; s/ $//')"

printf '%s\n' "$_cf_updated" | sudo tee "$_cf_cmdline_file" >/dev/null
