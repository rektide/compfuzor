# disable.sh - Disable config drop-ins by moving them to the disabled directory
#
# Accepts glob patterns. Matching files are moved from etc/${CONFIG_KEY}/
# to etc/${CONFIG_KEY}-disabled/ and the config merger is re-run.
#
# ENV:
#   CONFIG_KEY - drop-in directory name under etc/ (required)
#   CONFIG_EXT - file extension to match (default: yaml)

shopt -s nullglob

_len() { echo $#; }

dir="{{DIR}}"
key="${CONFIG_KEY:?CONFIG_KEY is required}"
ext="${CONFIG_EXT:-yaml}"
mkdir -p "${dir}/etc/${key}-disabled"

files=()
for pattern in "$@"; do
  if [ -f "$pattern" ]; then
    files+=("$pattern")
    continue
  fi

  orig_pattern="$pattern"
  before=$(_len "${files[@]}")

  pattern="${pattern%.${ext}}"
  for cfg_file in ${dir}/etc/${key}/*.${ext}; do
    filename=$(basename "$cfg_file")
    [[ "$filename" =~ $pattern ]] && files+=("$cfg_file") && continue
    [[ "${filename%.${ext}}" =~ $pattern ]] && files+=("$cfg_file")
  done

  after=$(_len "${files[@]}")
  [ $before -eq $after ] && echo "no match: $orig_pattern"
done

for cfg_file in "${files[@]}"; do
  filename=$(basename "$cfg_file")
  target="${dir}/etc/${key}-disabled/$filename"

  if [ -f "$target" ]; then
    echo "skipped (already disabled): $filename"
    continue
  fi

  mv "$cfg_file" "$target"
  echo "disabled: $filename"
done

[ -f "${dir}/bin/config-{{CONFIG_KEY}}.sh" ] && (cd "$dir" && "./bin/config-{{CONFIG_KEY}}.sh")
