# config.sh - Assemble drop-in YAML fragments into a single config
#
# Gathers all *.yaml from ${CONFIG_KEY}/ and concatenates as a YAML list.
# Disabled items are excluded (they live in ${CONFIG_KEY}-disabled/).
#
# --check compares the assembled output against ${CONFIG_OUTPUT} without
# writing: exits 0 if identical, 1 if drifted (prints a diff unless -q).
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

tmp=$(mktemp)
trap "rm -f $tmp" EXIT

for f in "${active[@]}"; do
  cat "$f"
  echo
done > "$tmp"

if [ "$CHECK" -eq 1 ]; then
  if [ ! -f "$CONFIG_OUTPUT" ]; then
    if [ "$QUIET" -eq 0 ]; then
      echo "${key}: drift: missing ${CONFIG_OUTPUT}" >&2
    fi
    exit 1
  fi
  if cmp -s "$tmp" "$CONFIG_OUTPUT"; then
    exit 0
  fi
  if [ "$QUIET" -eq 0 ]; then
    diff -u "$CONFIG_OUTPUT" "$tmp" || true
  fi
  exit 1
fi

mkdir -p "$(dirname "$CONFIG_OUTPUT")"
if [ -f "$CONFIG_OUTPUT" ] && cmp -s "$tmp" "$CONFIG_OUTPUT"; then
  echo "${key}: no changes"
  exit 0
fi

mv "$tmp" "$CONFIG_OUTPUT"
echo "${key}: assembled ${count} fragments -> ${CONFIG_OUTPUT}"
