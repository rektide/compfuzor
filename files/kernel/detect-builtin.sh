# Resolve target module name.
# - If arg is provided, use it directly.
# - If arg is omitted, derive the module from KERNEL_MODULES_JSON, but only if
#   exactly one module is defined.
_cf_module="${1:-}"
if [ -z "$_cf_module" ]; then
  : "${KERNEL_MODULES_JSON:?KERNEL_MODULES_JSON is required when module arg is omitted}"

  _cf_count="$(jq -r 'keys | length' "$KERNEL_MODULES_JSON")"
  if [ "$_cf_count" = "1" ]; then
    _cf_module="$(jq -r 'keys[0]' "$KERNEL_MODULES_JSON")"
  elif [ "$_cf_count" = "0" ]; then
    printf 'detect-builtin: no modules defined in KERNEL_MODULES_JSON\n' >&2
    exit 1
  else
    printf 'detect-builtin: module arg required when %s modules are defined\n' "$_cf_count" >&2
    exit 1
  fi
fi

if [ -e "/sys/module/${_cf_module}" ] && [ ! -e "/sys/module/${_cf_module}/sections" ]; then
  printf 'builtin\n'
  exit 0
fi

if [ -e "/sys/module/${_cf_module}" ] || modinfo "$_cf_module" >/dev/null 2>&1; then
  printf 'module\n'
  exit 0
fi

exit 1
