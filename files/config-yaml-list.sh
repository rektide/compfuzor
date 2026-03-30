# config.sh - Assemble drop-in YAML fragments into a single config
#
# Gathers all *.yaml from ${CONFIG_KEY}/ and concatenates as a YAML list.
# Disabled items are excluded (they live in ${CONFIG_KEY}-disabled/).
#
# ENV:
#   CONFIG_KEY     - drop-in directory name under etc/ (required)
#   CONFIG_OUTPUT  - output filename (default: ${CONFIG_KEY}.yaml)

shopt -s nullglob

dir="{{DIR}}"
key="${CONFIG_KEY:?CONFIG_KEY is required}"
output="${CONFIG_OUTPUT:-${key}.yaml}"
active=(${dir}/etc/${key}/*.yaml)

if [ ${#active[@]} -eq 0 ]; then
  echo "no ${key} configs found" >&2
  exit 0
fi

tmp=$(mktemp)
trap "rm -f $tmp" EXIT

for f in "${active[@]}"; do
  cat "$f"
  echo
done > "$tmp"

if [ -f "${dir}/etc/${output}" ] && cmp -s "$tmp" "${dir}/etc/${output}"; then
  echo "${key}: no changes"
  exit 0
fi

mv "$tmp" "${dir}/etc/${output}"
echo "${key}: assembled ${#active[@]} fragments -> etc/${output}"
