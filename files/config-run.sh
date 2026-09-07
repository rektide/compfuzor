#!/bin/bash
# Build, validate, and atomically commit compiled configs.

spec="$DIR/etc/config.spec.json"
check=0
quiet=0
print=0
target=""
list=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) check=1 ;;
    --stdout) print=1 ;;
    --list) list=1 ;;
    -q|--quiet) quiet=1 ;;
    --target) shift; target="${1:?--target requires a config name}" ;;
    -*) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
    *)
      [ -z "$target" ] || { printf 'unexpected argument: %s\n' "$1" >&2; exit 2; }
      target="$1"
      ;;
  esac
  shift
done

if [ "$print" = 1 ] && [ "$check" = 1 ]; then
  printf '%s\n' '--stdout and --check are mutually exclusive' >&2
  exit 2
fi

[ -f "$spec" ] || { printf 'missing config spec: %s\n' "$spec" >&2; exit 2; }
if [ "$list" = 1 ]; then
  [ -z "$target" ] || { printf '--list does not accept a target\n' >&2; exit 2; }
  jq -r '.configs | keys[]' "$spec"
  exit
fi
if [ -n "$target" ]; then
  jq -e --arg target "$target" '.configs[$target]' "$spec" >/dev/null || {
    printf 'unknown config: %s\n' "$target" >&2; exit 2;
  }
  configs=("$target")
else
  mapfile -t configs < <(jq -r '.configs | to_entries[] | select(.value.apply) | .key' "$spec")
fi

transaction=$(mktemp -d)
temps=()
cleanup() { rm -rf "$transaction"; for file in "${temps[@]}"; do rm -f "$file"; done; }
trap cleanup EXIT
drift=0
pending_sources=()
pending_outputs=()

for config in "${configs[@]}"; do
    output=$(jq -r --arg config "$config" '.configs[$config].output' "$spec")
    validate=$(jq -r --arg config "$config" '.configs[$config].validate // empty' "$spec")
    input_manifest="$transaction/inputs"
    : > "$input_manifest"

    input_index=0
    while IFS=$'\t' read -r kind value pattern block; do
      case "$kind" in
        file) printf 'file\tfile/%s/%s\t%s\t%s\n' "$input_index" "$(basename "$value")" "$value" "$block" >> "$input_manifest" ;;
        glob)
          while IFS= read -r -d '' file; do
            filename=$(basename "$file")
            printf 'glob\t%s/%s/%s\t%s\t%s\n' "$(basename "$value")" "$input_index" "$filename" "$file" "$block" >> "$input_manifest"
          done < <(find -L "$value" -maxdepth 1 -type f -name "$pattern" -print0 | sort -z)
          ;;
      esac
      input_index=$((input_index + 1))
    done < <(jq -r --arg config "$config" '
      .configs[$config].inputs[] |
      (.block // {} | tojson) as $block |
      if has("file") then ["file", .file, "", $block]
      else ["glob", .directory, .pattern, $block]
      end | @tsv
    ' "$spec")

    # --stdout is a pure generate: build the candidate in the transaction dir
    # (never touches the output directory) and stream it. With an explicit
    # target the stream is byte-exact candidate output, ready for
    # `config.sh --stdout NAME | diff - $output`; with no target each config
    # gets a `# ---- config: NAME ----` separator header.
    if [ "$print" = 1 ]; then
      tmp=$(mktemp "$transaction/candidate.XXXXXX")
    else
      tmp=$(mktemp "$(dirname "$output")/.config-candidate.XXXXXX")
    fi
    leaf="$DIR/bin/internal/config/$config"
    [ -x "$leaf" ] || { printf 'missing config leaf: %s\n' "$leaf" >&2; exit 2; }
    if [ "$print" = 1 ]; then
      # processor chatter (banners, per-input progress) must not pollute the stream
      if ! CONFIG_TRANSACTION="$transaction" CONFIG_CANDIDATE="$tmp" CONFIG_INPUTS_FILE="$input_manifest" \
        "$leaf" --config "$config" >&2; then
        printf '%s: processor failed\n' "$config" >&2
        exit 1
      fi
    elif ! CONFIG_TRANSACTION="$transaction" CONFIG_CANDIDATE="$tmp" CONFIG_INPUTS_FILE="$input_manifest" \
      "$leaf" --config "$config"; then
      printf '%s: processor failed\n' "$config" >&2
      exit 1
    fi

    if [ -n "$validate" ]; then
      if [ "$print" = 1 ]; then
        CONFIG_CANDIDATE="$tmp" bash -c "$validate" >&2 || { printf '%s: candidate validation failed\n' "$config" >&2; exit 1; }
      else
        CONFIG_CANDIDATE="$tmp" bash -c "$validate" || { printf '%s: candidate validation failed\n' "$config" >&2; exit 1; }
      fi
    fi
    if [ "$print" = 1 ]; then
      [ -n "$target" ] || printf '# ---- config: %s ----\n' "$config"
      cat "$tmp"
      rm -f "$tmp"
      continue
    fi
    if [ -f "$output" ] && cmp -s "$tmp" "$output"; then
      rm -f "$tmp"; continue
    fi
    temps+=("$tmp")
    if [ "$check" = 1 ]; then
      drift=1
      if [ "$quiet" = 0 ]; then
        if [ -f "$output" ]; then diff -u "$output" "$tmp" || true; else printf 'missing: %s\n' "$output"; fi
      fi
    else
      pending_sources+=("$tmp"); pending_outputs+=("$output")
    fi
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
