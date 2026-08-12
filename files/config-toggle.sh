# Toggle compiled drop-in fragments with a .disabled-style suffix.

CONFIG_ACTION=${1:?config action is required}
CONFIG_NAME=${2:?config name is required}
INPUT_NAME=${3:?input name is required}
shift 3
[ "$#" -gt 0 ] || { printf 'usage: %s pattern [...]\n' "$0" >&2; exit 2; }

spec="$DIR/etc/config.spec.json"
[ -f "$spec" ] || { printf 'missing config spec: %s\n' "$spec" >&2; exit 2; }

sources=()
targets=()
declare -A seen_sources
declare -A seen_targets
errors=0
for selector in "$@"; do
  pattern="$selector"
  matched=0

  while IFS=$'\t' read -r path include suffix; do
    [ -n "$suffix" ] || continue

    search="$include"
    [ "$CONFIG_ACTION" = enable ] && search="${include}${suffix}"
    while IFS= read -r -d '' file; do
      basename=$(basename "$file")
      active_name=${basename%"$suffix"}
      stem=${active_name%.*}
      if [[ "$file" != "$pattern" && "$file" != "$path/$pattern" && "$active_name" != $pattern && "$stem" != $pattern ]]; then continue; fi
      if [ "$CONFIG_ACTION" = disable ]; then target="${file}${suffix}"; else target=${file%"$suffix"}; fi
      if [ -n "${seen_sources[$file]:-}" ]; then
        matched=1
        continue
      fi
      if [ -n "${seen_targets[$target]:-}" ]; then
        printf 'duplicate target: %s\n' "$target" >&2
        errors=1
        continue
      fi
      seen_sources["$file"]=1
      seen_targets["$target"]=1
      sources+=("$file")
      targets+=("$target")
      matched=1
    done < <(find "$path" -maxdepth 1 -type f -name "$search" -print0 | sort -z)
  done < <(jq -r --arg config "$CONFIG_NAME" --arg input "$INPUT_NAME" '
    .configs[$config].inputs[] | select(.glob and .name == $input) |
    [.directory, .pattern, (.disabled_suffix // "")] | @tsv
  ' "$spec")

  if [ "$matched" != 1 ]; then
    printf 'no match: %s\n' "$selector" >&2
    errors=1
  fi
done

[ "$errors" = 0 ] || exit 1
[ "${{ '{#' }}sources[@]}" -gt 0 ] || exit 1
for target in "${targets[@]}"; do
  [ ! -e "$target" ] || { printf 'target exists: %s\n' "$target" >&2; exit 1; }
done
for index in "${!sources[@]}"; do
  if ! mv "${sources[$index]}" "${targets[$index]}"; then
    for ((rollback=index - 1; rollback >= 0; rollback--)); do
      mv "${targets[$rollback]}" "${sources[$rollback]}" || true
    done
    exit 1
  fi
  printf '%s: %s -> %s\n' "$CONFIG_ACTION" "${sources[$index]}" "${targets[$index]}"
done

exec "$DIR/bin/config-${CONFIG_NAME}.sh"
