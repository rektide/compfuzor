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
      # key=value form: replace by key prefix, or append.
      _cf_key="${_cf_line%%=*}"
      if printf '%s\n' "$_cf_updated" | grep -Eq "(^|[[:space:]])${_cf_key}="; then
        _cf_updated="$(printf '%s\n' "$_cf_updated" | sed -E "s#(^|[[:space:]])${_cf_key}=[^[:space:]]*#\\1${_cf_line}#")"
      else
        _cf_updated="${_cf_updated} ${_cf_line}"
      fi
      ;;
    *)
      # flag form: idempotent add (compare token-by-token to avoid glob surprises).
      _cf_present=0
      for _cf_tok in $_cf_updated; do
        [ "$_cf_tok" = "$_cf_line" ] && _cf_present=1
      done
      [ "$_cf_present" = "0" ] && _cf_updated="${_cf_updated} ${_cf_line}"
      ;;
  esac
done < <(jq -r '.[]' "$KERNEL_PARAMS_JSON")

_cf_updated="$(printf '%s\n' "$_cf_updated" | tr -s '[:space:]' ' ' | sed -E 's/^ //; s/ $//')"

printf '%s\n' "$_cf_updated" | sudo tee "$_cf_cmdline_file" >/dev/null
