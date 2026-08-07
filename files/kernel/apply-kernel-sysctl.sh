# apply-kernel-sysctl.sh — apply desired sysctl values to the live kernel.
#
# Reads $KERNEL_SYSCTL_JSON, NOT /etc/sysctl.d/*, so apply is independent of
# install (install persists to /etc for reboot; this sets live values now).
#
# Default: for each key, print `key: <live> -> <desired>` (live read via
# `sysctl -n`, no sudo) then apply with `sudo sysctl -w key=value`. With -q the
# preamble is skipped and only the apply runs.
#
# Only the `sudo sysctl -w` writes escalate; this bin itself runs as the
# invoking user.

: "${KERNEL_SYSCTL_JSON:?KERNEL_SYSCTL_JSON is required}"

quiet=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -q) quiet=1; shift ;;
    -h|--help)
      cat >&2 <<'EOF'
usage: apply-kernel-sysctl.sh [-q]
  Apply KERNEL_SYSCTL_JSON to the live kernel via `sudo sysctl -w`.
  -q   quiet: skip the per-key live -> desired preamble.
EOF
      exit 0 ;;
    *) printf 'apply-kernel-sysctl.sh: unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# key<TAB>value per line; fail fast (exit 2) on unreadable or invalid JSON
entries=$(jq -r 'to_entries | sort_by(.key) | .[] | "\(.key)\t\(.value|tostring)"' "$KERNEL_SYSCTL_JSON") || exit 2

failed=0
while IFS=$'\t' read -r key desired; do
  [ -n "$key" ] || continue
  if [ "$quiet" -eq 0 ]; then
    live=$(sysctl -n "$key" 2>/dev/null || printf '<unset>')
    printf '%s: %s -> %s\n' "$key" "$live" "$desired"
  fi
  if sudo sysctl -w "${key}=${desired}"; then
    :
  else
    printf 'apply-kernel-sysctl.sh: failed to set %s\n' "$key" >&2
    failed=$((failed + 1))
  fi
done <<< "$entries"

if [ "$failed" -eq 0 ]; then exit 0; else exit 1; fi
