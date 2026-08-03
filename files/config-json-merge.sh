# config-json-merge.sh - Deep-merge JSON drop-in fragments into one config
#
# Gathers all *.json from ${CONFIG_KEY}/, deep-merges them with jq, and
# writes the combined result to ${CONFIG_OUTPUT}.
# Disabled items in ${CONFIG_KEY}-disabled/ are included last so their
# overrides (e.g. {"enabled": false}) take precedence.
#
# ENV:
#   CONFIG_KEY     - drop-in directory name under etc/ (required)
#   CONFIG_OUTPUT  - output path (required; full path)

shopt -s nullglob

dir="{{DIR}}"
key="${CONFIG_KEY:?CONFIG_KEY is required}"
: "${CONFIG_OUTPUT:?CONFIG_OUTPUT is required}"

configs=("${dir}/etc/${key}"/*.json)
disabled=("${dir}/etc/${key}-disabled"/*.json)

if [ ${{ '{#' }}configs[@]} -eq 0 ]; then
  echo "no ${key} configs found" >&2
  exit 0
fi

base_files=()
[ -f "${dir}/etc/base.json" ] && base_files=("${dir}/etc/base.json")

tmp=$(mktemp)
trap "rm -f $tmp" EXIT
jq -s 'reduce .[] as $item ({}; . * $item)' "${base_files[@]}" "${configs[@]}" "${disabled[@]}" > "$tmp"

drift=0
if [ ! -f "$CONFIG_OUTPUT" ]; then
  drift=1
elif ! cmp -s "$tmp" "$CONFIG_OUTPUT"; then
  drift=1
fi

if [ $drift -eq 0 ]; then
  exit 0
fi

if [ -f "$CONFIG_OUTPUT" ]; then
  diff -u "$CONFIG_OUTPUT" "$tmp" || true
fi
mkdir -p "$(dirname "$CONFIG_OUTPUT")"
mv "$tmp" "$CONFIG_OUTPUT"
echo "${key}: merged ${{ '{#' }}configs[@]} fragments -> ${CONFIG_OUTPUT}"
