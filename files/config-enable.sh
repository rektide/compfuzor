# enable.sh - Re-enable config drop-ins by moving them back to the active directory
#
# Accepts glob patterns. Matching files are moved from etc/${CONFIG_key}-disabled/
# to etc/${config_key}/ and config.sh is re-run.
#
# ENV:
#   CONFIG_KEY - drop-in directory name under etc/ (required)

shopt -s nullglob

_len() { echo ${!*[@]}; }

dir="{{DIR}}"
key="${CONFIG_KEY:?CONFIG_KEY is required}"
files=()
for pattern in "$@"; do
  if [ -f "$pattern" ]; then
    files+=("$pattern")
    continue
  fi

  orig_pattern="$pattern"
  before=$(_len files)

  pattern="${pattern%.yaml}"
  for yaml_file in ${dir}/etc/${key}-disabled/*.yaml; do
    filename=$(basename "$yaml_file")
    [[ "$filename" =~ $pattern ]] && files+=("$yaml_file") && continue
    [[ "${filename%.yaml}" =~ $pattern ]] && files+=("$yaml_file")
  done

  after=$(_len files)
  [ $before -eq $after ] && echo "no match: $orig_pattern"
done

for yaml_file in "${files[@]}"; do
  filename=$(basename "$yaml_file")
  target="${dir}/etc/${key}/$filename"

  if [ -f "$target" ]; then
    echo "skipped (already active): $filename"
    continue
  fi

  mv "$yaml_file" "$target"
  echo "enabled: $filename"
done

[ -f "${dir}/bin/config.sh" ] && (cd "$dir" && ./bin/config.sh)
