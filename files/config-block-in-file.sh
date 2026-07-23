# config-block-in-file.sh - Assemble drop-in fragments via block-in-file
#
# For each fragment in etc/${CONFIG_KEY}/*.${CONFIG_EXT}, inserts it as
# a named block into CONFIG_OUTPUT. Block names: ${NAME}-${CONFIG_KEY}-${stem}
#
# Disabled items are excluded (they live in etc/${CONFIG_KEY}-disabled/).
#
# By default (write mode) blocks are applied to ${CONFIG_OUTPUT}: silently
# when nothing changed, printing a diff when they do. --check compares
# without writing: exits 0 clean / 1 drift (diff unless -q).
#
# ENV:
#   CONFIG_KEY     - drop-in directory name under etc/ (required)
#   CONFIG_OUTPUT  - target file to insert blocks into (required)
#   CONFIG_EXT     - file extension to glob (default: ${CONFIG_KEY})

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

: "${CONFIG_KEY:?CONFIG_KEY is required}"
: "${CONFIG_OUTPUT:?CONFIG_OUTPUT is required}"
ext="${CONFIG_EXT:-${CONFIG_KEY}}"
name="${NAME:-{{NAME}}}"

active=("${DIR}/etc/${CONFIG_KEY}"/*.${ext})

count=$(_len "${active[@]}")
if [ $count -eq 0 ]; then
  echo "${CONFIG_KEY}: no configs found" >&2
  exit 0
fi

# build desired output: seed from current, apply all blocks
tmp=$(mktemp)
trap "rm -f $tmp" EXIT
if [ -f "$CONFIG_OUTPUT" ]; then
  cp "$CONFIG_OUTPUT" "$tmp"
fi
for f in "${active[@]}"; do
  stem=$(basename "$f" ".${ext}")
  block-in-file -n "${name}-${CONFIG_KEY}-${stem}" -i "$f" -o "$tmp" >/dev/null
done

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
touch "$CONFIG_OUTPUT"
for f in "${active[@]}"; do
  stem=$(basename "$f" ".${ext}")
  block-in-file -n "${name}-${CONFIG_KEY}-${stem}" -i "$f" -o "$CONFIG_OUTPUT"
done
echo "${CONFIG_KEY}: assembled ${count} drop-in blocks -> ${CONFIG_OUTPUT}"
