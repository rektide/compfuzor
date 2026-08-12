#!/bin/bash
# Build, validate, and atomically commit compiled config assembly graphs.

spec="$DIR/etc/config.spec.json"
check=0
quiet=0
instance=""
target=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) check=1 ;;
    -q|--quiet) quiet=1 ;;
    --target) shift; target="${1:?--target requires instance/assembly}" ;;
    -*) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
    *)
      [ -z "$instance" ] || { printf 'unexpected argument: %s\n' "$1" >&2; exit 2; }
      instance="$1"
      ;;
  esac
  shift
done

[ -f "$spec" ] || { printf 'missing config spec: %s\n' "$spec" >&2; exit 2; }
if [ -n "$target" ]; then
  [ -z "$instance" ] || { printf 'instance and --target are mutually exclusive\n' >&2; exit 2; }
  instance=${target%%/*}
  target_assembly=${target#*/}
  [ "$instance" != "$target" ] && [ -n "$target_assembly" ] || {
    printf 'target must be instance/assembly: %s\n' "$target" >&2; exit 2;
  }
fi

if [ -n "$instance" ]; then
  jq -e --arg instance "$instance" '.configs[$instance]' "$spec" >/dev/null || {
    printf 'unknown config instance: %s\n' "$instance" >&2; exit 2;
  }
  instances=("$instance")
else
  mapfile -t instances < <(jq -r '.configs | to_entries[] | select(.value.apply) | .key' "$spec")
fi

transaction=$(mktemp -d)
temps=()
cleanup() { rm -rf "$transaction"; for file in "${temps[@]}"; do rm -f "$file"; done; }
trap cleanup EXIT
drift=0
declare -A candidates
pending_sources=()
pending_outputs=()

for instance in "${instances[@]}"; do
  if [ -n "$target" ]; then
    jq -e --arg i "$instance" --arg a "$target_assembly" '.configs[$i].assemblies[$a]' "$spec" >/dev/null || {
      printf 'unknown config assembly: %s\n' "$target" >&2; exit 2;
    }
    mapfile -t assemblies < <(jq -r --arg i "$instance" --arg target "$target_assembly" '
      .configs[$i] as $config |
      def dependencies($name):
        $name, ($config.assemblies[$name].inputs[]? | select(has("artifact")) | .artifact | dependencies(.));
      [dependencies($target)] | unique as $needed |
      $config.order[] | select(. as $name | $needed | index($name))
    ' "$spec")
  else
    mapfile -t assemblies < <(jq -r --arg instance "$instance" '.configs[$instance].order[]' "$spec")
  fi

  for assembly in "${assemblies[@]}"; do
    output=$(jq -r --arg i "$instance" --arg a "$assembly" '.configs[$i].assemblies[$a].output' "$spec")
    validate=$(jq -r --arg i "$instance" --arg a "$assembly" '.configs[$i].assemblies[$a].validate // empty' "$spec")
    input_manifest="$transaction/inputs"
    : > "$input_manifest"

    while IFS=$'\t' read -r kind value fallback block; do
      case "$kind" in
        file) printf 'file\tfile/%s\t%s\t%s\n' "$(basename "$value")" "$value" "$block" >> "$input_manifest" ;;
        artifact)
          candidate_key="${instance}.${value}"
          printf 'artifact\tartifact/%s\t%s\t%s\n' "$value" "${candidates[$candidate_key]:-$fallback}" "$block" >> "$input_manifest"
          ;;
        dropins)
          dropin_path=$(jq -r --arg name "$value" '.dropins[$name].path' "$spec")
          include=$(jq -r --arg name "$value" '.dropins[$name].include' "$spec")
          while IFS= read -r -d '' file; do
            stem=$(basename "$file"); stem=${stem%.*}
            printf 'dropins\t%s/%s\t%s\t%s\n' "$value" "$stem" "$file" "$block" >> "$input_manifest"
          done < <(find "$dropin_path" -maxdepth 1 -type f -name "$include" -print0 | sort -z)
          ;;
      esac
    done < <(jq -r --arg i "$instance" --arg a "$assembly" '
      .configs[$i].assemblies[$a].inputs[] |
      (.block // {} | tojson) as $block |
      if has("file") then ["file", .file, "", $block]
      elif has("dropins") then ["dropins", .dropins, "", $block]
      else ["artifact", .artifact, .path, $block]
      end | @tsv
    ' "$spec")

    tmp=$(mktemp "$(dirname "$output")/.config-candidate.XXXXXX")
    leaf="$DIR/bin/internal/config/$instance/$assembly"
    [ -x "$leaf" ] || { printf 'missing config leaf: %s\n' "$leaf" >&2; exit 2; }
    CONFIG_TRANSACTION="$transaction" CONFIG_CANDIDATE="$tmp" CONFIG_INPUTS_FILE="$input_manifest" \
      "$leaf" --instance "$instance" --assembly "$assembly"

    if [ -n "$validate" ] && ! CONFIG_CANDIDATE="$tmp" bash -c "$validate"; then
      printf '%s/%s: candidate validation failed\n' "$instance" "$assembly" >&2; exit 1
    fi
    if [ -f "$output" ] && cmp -s "$tmp" "$output"; then
      rm -f "$tmp"; candidates["${instance}.${assembly}"]="$output"; continue
    fi
    candidates["${instance}.${assembly}"]="$tmp"; temps+=("$tmp")
    if [ "$check" = 1 ]; then
      drift=1
      if [ "$quiet" = 0 ]; then
        if [ -f "$output" ]; then diff -u "$output" "$tmp" || true; else printf 'missing: %s\n' "$output"; fi
      fi
    else
      pending_sources+=("$tmp"); pending_outputs+=("$output")
    fi
  done
done

if [ "$check" = 0 ]; then
  backups=()
  for output in "${pending_outputs[@]}"; do
    [ ! -e "$output" ] || [ -f "$output" ] || { printf 'config output is not a regular file: %s\n' "$output" >&2; exit 1; }
  done
  for index in "${!pending_sources[@]}"; do
    output=${pending_outputs[$index]}; backup=""
    if [ -e "$output" ]; then
      backup=$(mktemp "$(dirname "$output")/.config-backup.XXXXXX"); rm -f "$backup"
      if ! mv "$output" "$backup"; then
        for ((rollback=index - 1; rollback >= 0; rollback--)); do rm -f "${pending_outputs[$rollback]}"; [ -z "${backups[$rollback]}" ] || mv "${backups[$rollback]}" "${pending_outputs[$rollback]}"; done
        exit 1
      fi
    fi
    backups[$index]="$backup"
    if ! mv "${pending_sources[$index]}" "$output"; then
      [ -z "$backup" ] || mv "$backup" "$output"
      for ((rollback=index - 1; rollback >= 0; rollback--)); do rm -f "${pending_outputs[$rollback]}"; [ -z "${backups[$rollback]}" ] || mv "${backups[$rollback]}" "${pending_outputs[$rollback]}"; done
      exit 1
    fi
    printf 'assembled -> %s\n' "$output"
  done
  for backup in "${backups[@]}"; do [ -z "$backup" ] || rm -f "$backup"; done
fi
exit "$drift"
