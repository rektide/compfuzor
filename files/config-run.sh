# Apply compiled config assembly graphs.

spec="$DIR/etc/config.spec.json"
check=0
quiet=0
instance=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) check=1 ;;
    -q|--quiet) quiet=1 ;;
    -*) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
    *)
      if [ -n "$instance" ]; then
        printf 'unexpected argument: %s\n' "$1" >&2
        exit 2
      fi
      instance="$1"
      ;;
  esac
  shift
done

[ -f "$spec" ] || { printf 'missing config spec: %s\n' "$spec" >&2; exit 2; }

if [ -n "$instance" ]; then
  jq -e --arg instance "$instance" '.configs[$instance]' "$spec" >/dev/null || {
    printf 'unknown config instance: %s\n' "$instance" >&2
    exit 2
  }
  instances=("$instance")
else
  mapfile -t instances < <(jq -r '.configs | to_entries[] | select(.value.apply) | .key' "$spec")
fi

drift=0
declare -A candidates
temps=()
cleanup() { for file in "${temps[@]}"; do rm -f "$file"; done; }
trap cleanup EXIT
for instance in "${instances[@]}"; do
  mapfile -t assemblies < <(jq -r --arg instance "$instance" '.configs[$instance].order[]' "$spec")
  for assembly in "${assemblies[@]}"; do
    output=$(jq -r --arg instance "$instance" --arg assembly "$assembly" '.configs[$instance].assemblies[$assembly].output' "$spec")
    processor=$(jq -r --arg instance "$instance" --arg assembly "$assembly" '.configs[$instance].assemblies[$assembly].processor' "$spec")
    files=()

    while IFS=$'\t' read -r kind value fallback; do
      case "$kind" in
        file)
          files+=("$value")
          ;;
        artifact)
          candidate_key="${instance}.${value}"
          files+=("${candidates[$candidate_key]:-$fallback}")
          ;;
        dropins)
          dropin_path=$(jq -r --arg name "$value" '.dropins[$name].path' "$spec")
          include=$(jq -r --arg name "$value" '.dropins[$name].include' "$spec")
          while IFS= read -r -d '' file; do
            files+=("$file")
          done < <(find "$dropin_path" -maxdepth 1 -type f -name "$include" -print0 | sort -z)
          ;;
      esac
    done < <(jq -r --arg instance "$instance" --arg assembly "$assembly" '
      .configs[$instance].assemblies[$assembly].inputs[] |
      if has("file") then ["file", .file, ""]
      elif has("dropins") then ["dropins", .dropins, ""]
      else ["artifact", .artifact, .path]
      end | @tsv
    ' "$spec")

    tmp=$(mktemp "$(dirname "$output")/.config-candidate.XXXXXX")
    case "$processor" in
      concat)
        : > "$tmp"
        for file in "${files[@]}"; do cat "$file" >> "$tmp"; done
        ;;
      json-deep-merge)
        if [ "${{ '{#' }}files[@]}" -eq 0 ]; then
          printf '{}\n' > "$tmp"
        else
          jq -s 'reduce .[] as $item ({}; . * $item)' "${files[@]}" > "$tmp"
        fi
        ;;
      *)
        printf 'unsupported config processor: %s\n' "$processor" >&2
        rm -f "$tmp"
        exit 2
        ;;
    esac

    if [ -f "$output" ] && cmp -s "$tmp" "$output"; then
      rm -f "$tmp"
      candidates["${instance}.${assembly}"]="$output"
      continue
    fi

    if [ "$check" = 1 ]; then
      drift=1
      if [ "$quiet" = 0 ]; then
        if [ -f "$output" ]; then diff -u "$output" "$tmp" || true; else printf 'missing: %s\n' "$output"; fi
      fi
      candidates["${instance}.${assembly}"]="$tmp"
      temps+=("$tmp")
      continue
    fi

    mv "$tmp" "$output"
    candidates["${instance}.${assembly}"]="$output"
    printf '%s.%s: assembled -> %s\n' "$instance" "$assembly" "$output"
  done
done

exit "$drift"
