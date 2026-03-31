# config-block-in-file.sh - Assemble drop-in fragments via block-in-file
#
# For each fragment in etc/${CONFIG_KEY}/*.${CONFIG_EXT}, inserts it as
# a named block into CONFIG_OUTPUT. Block names: ${NAME}-${CONFIG_KEY}-${stem}
#
# Disabled items are excluded (they live in etc/${CONFIG_KEY}-disabled/).
#
# ENV:
#   CONFIG_KEY     - drop-in directory name under etc/ (required)
#   CONFIG_OUTPUT  - target file to insert blocks into (required)
#   CONFIG_EXT     - file extension to glob (default: ${CONFIG_KEY})

shopt -s nullglob

_len() { echo ${!*[@]}; }

: "${CONFIG_KEY:?CONFIG_KEY is required}"
: "${CONFIG_OUTPUT:?CONFIG_OUTPUT is required}"
ext="${CONFIG_EXT:-${CONFIG_KEY}}"
name="${NAME:-{{NAME}}}"

active=("${DIR}/etc/${CONFIG_KEY}"/*.${ext})

count=$(_len active)
if [ $count -eq 0 ]; then
  echo "${CONFIG_KEY}: no configs found" >&2
  exit 0
fi

mkdir -p "$(dirname "$CONFIG_OUTPUT")"
touch "$CONFIG_OUTPUT"

for f in "${active[@]}"; do
  stem=$(basename "$f" ".${ext}")
  block-in-file -n "${name}-${CONFIG_KEY}-${stem}" -i "$f" -o "$CONFIG_OUTPUT"
done

echo "${CONFIG_KEY}: assembled ${count} drop-in blocks -> ${CONFIG_OUTPUT}"
