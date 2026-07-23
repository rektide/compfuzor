# config.sh - Assemble drop-in YAML fragments into a single config
#
# Gathers all *.yaml from ${CONFIG_KEY}/ and concatenates as a YAML list.
# Disabled items are excluded (they live in ${CONFIG_KEY}-disabled/).
#
# By default (write mode) the assembled output replaces ${CONFIG_OUTPUT}:
# silently when nothing changed, printing a diff when it does.
# --check compares without writing: exits 0 clean / 1 drift (diff unless -q).
#
# ENV:
#   CONFIG_KEY     - drop-in directory name under etc/ (required)
#   CONFIG_OUTPUT  - output path (required; full path)

shopt -s nullglob

_len() { echo $#; }

CHECK=0
QUIET=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    -q|--quiet) QUIET=1; shift ;;
    *) shift ;;
  esac
done

dir="{{DIR}}"
key="${CONFIG_KEY:?CONFIG_KEY is required}"
: "${CONFIG_OUTPUT:?CONFIG_OUTPUT is required}"
active=("${dir}/etc/${key}"/*.yaml)

count=$(_len "${active[@]}")
if [ $count -eq 0 ]; then
  echo "no ${key} configs found" >&2
  exit 0
fi

# build desired output
tmp=$(mktemp)
trap "rm -f $tmp" EXIT
for f in "${active[@]}"; do
  cat "$f"
  echo
done > "$tmp"

# drift = desired differs from current (or current missing)
drift=0
if [ ! -f "$CONFIG_OUTPUT" ]; then
  drift=1
elif ! cmp -s "$tmp" "$CONFIG_OUTPUT"; then
  drift=1
fi

show_diff() {
  if [ -f "$CONFIG_OUTPUT" ]; then
    diff -u "$CONFIG_OUTPUT" "$tmp" || true
  else
    cat "$tmp"
  fi
}

if [ "$CHECK" -eq 1 ]; then
  if [ $drift -eq 0 ]; then
    exit 0
  fi
  if [ "$QUIET" -eq 0 ]; then
    show_diff
  fi
  exit 1
fi

# write mode: silent on no change, diff + write on change
if [ $drift -eq 0 ]; then
  exit 0
fi
show_diff
mkdir -p "$(dirname "$CONFIG_OUTPUT")"
mv "$tmp" "$CONFIG_OUTPUT"
echo "${key}: assembled ${count} fragments -> ${CONFIG_OUTPUT}"
