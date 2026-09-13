#!/bin/bash
# Build, validate, and atomically commit compiled configs.

set -euo pipefail

if [ -z "${DIR:-}" ]; then
  script=$(readlink -f -- "$0")
  DIR=$(dirname "$(dirname "$(dirname "$script")")")
  export DIR
fi
spec=${CONFIG_SPEC:-"$DIR/etc/config.spec.json"}
export CONFIG_SPEC="$spec"
check=0
quiet=0
print=0
targets=()
list=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) check=1 ;;
    --stdout) print=1 ;;
    --list) list=1 ;;
    -q|--quiet) quiet=1 ;;
    --target) shift; targets+=("${1:?--target requires a config name}") ;;
    -*) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
    *)
      targets+=("$1")
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
  [ "${#targets[@]}" -eq 0 ] || { printf '--list does not accept recipe names\n' >&2; exit 2; }
  jq -r '.configs | keys[]' "$spec"
  exit
fi
if [ "${#targets[@]}" -gt 0 ]; then
  declare -A seen_targets
  configs=()
  for target in "${targets[@]}"; do
    jq -e --arg target "$target" '.configs[$target]' "$spec" >/dev/null || {
      printf 'unknown config: %s\n' "$target" >&2; exit 2;
    }
    [ -z "${seen_targets[$target]:-}" ] || { printf 'config selected more than once: %s\n' "$target" >&2; exit 2; }
    seen_targets["$target"]=1
    configs+=("$target")
  done
else
  selected=$(jq -r '.configs | to_entries[] | select(.value.apply) | .key' "$spec")
  if [ -n "$selected" ]; then mapfile -t configs <<< "$selected"; else configs=(); fi
fi

if [ "$print" = 1 ] && [ "${#configs[@]}" -ne 1 ]; then
  printf '%s\n' '--stdout requires exactly one selected config' >&2
  exit 2
fi

transaction=$(mktemp -d)
temps=()
backups=()
cleanup() {
  rm -rf "$transaction" || true
  for file in "${temps[@]}"; do rm -f "$file" || true; done
}
warn() { printf '%s\n' "$*" >&2 || true; }
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
    input_rows="$transaction/input-rows-${config}"
    if ! jq -r --arg config "$config" '
      .configs[$config].inputs[] |
      (.block // {} | tojson) as $block |
       if has("file") then ["file", .file, "-", "-", $block]
       else ["glob", .directory, .pattern, (.disabled_suffix // "-"), $block]
      end | @tsv
    ' "$spec" > "$input_rows"; then
      printf '%s: failed to read compiled inputs\n' "$config" >&2
      exit 2
    fi
    while IFS=$'\t' read -r kind value pattern suffix block; do
      [ "$suffix" != "-" ] || suffix=""
      case "$kind" in
        file) printf 'file\tfile/%s/%s\t%s\t%s\n' "$input_index" "$(basename "$value")" "$value" "$block" >> "$input_manifest" ;;
        glob)
          [ -d "$value" ] || { printf '%s: config input directory is missing: %s\n' "$config" "$value" >&2; exit 1; }
          found="$transaction/found-${config}-${input_index}"
          sorted="$transaction/sorted-${config}-${input_index}"
          if ! find -L "$value" -maxdepth 1 -type f -name "$pattern" -print0 > "$found"; then
            printf '%s: failed to enumerate config input directory: %s\n' "$config" "$value" >&2
            exit 1
          fi
          if ! sort -z "$found" > "$sorted"; then
            printf '%s: failed to sort config inputs from: %s\n' "$config" "$value" >&2
            exit 1
          fi
          while IFS= read -r -d '' file; do
            filename=$(basename "$file")
            if [ -n "$suffix" ] && [[ "$filename" == *"$suffix" ]]; then continue; fi
            printf 'glob\t%s/%s/%s\t%s\t%s\n' "$(basename "$value")" "$input_index" "$filename" "$file" "$block" >> "$input_manifest"
          done < "$sorted"
          ;;
      esac
      input_index=$((input_index + 1))
    done < "$input_rows"

    # Every mode builds privately. Apply stages validated candidates beside
    # their outputs later, immediately before the atomic commit. Thus check and
    # stdout never require a writable destination directory.
    tmp=$(mktemp "$transaction/candidate.XXXXXX")
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
      cat "$tmp"
      rm -f "$tmp"
      continue
    fi
    # A matching symlink is still pending: assembly owns the directory entry
    # and must detach it rather than leave a link to (and later write into) a
    # donor output.
    if [ ! -L "$output" ] && [ -f "$output" ] && cmp -s "$tmp" "$output"; then
      rm -f "$tmp"; continue
    fi
    temps+=("$tmp")
    if [ "$check" = 1 ]; then
      drift=1
      if [ "$quiet" = 0 ]; then
        if [ -L "$output" ] && [ -f "$output" ] && cmp -s "$tmp" "$output"; then
          printf 'detach symlink: %s -> regular assembled output\n' "$output"
        elif [ -f "$output" ]; then diff -u "$output" "$tmp" || true
        else printf 'missing: %s\n' "$output"
        fi
      fi
    else
      pending_sources+=("$tmp"); pending_outputs+=("$output")
    fi
done

if [ "$check" = 0 ]; then
  staged_sources=()
  staged_outputs=()
  for index in "${!pending_sources[@]}"; do
    output=${pending_outputs[$index]}
    parent=$(dirname "$output")
    if [ -e "$output" ] || [ -L "$output" ]; then
      [ -L "$output" ] || [ -f "$output" ] || { printf 'config output is not a regular file or symlink: %s\n' "$output" >&2; exit 1; }
    fi
    mkdir -p "$parent"
    staged=$(mktemp "$parent/.config-candidate.XXXXXX")
    temps+=("$staged")
    mode=0600
    if [ ! -L "$output" ] && [ -f "$output" ]; then mode=$(stat -c '%a' -- "$output"); fi
    cp -- "${pending_sources[$index]}" "$staged"
    chmod "$mode" "$staged"
    staged_sources+=("$staged")
    staged_outputs+=("$output")
  done

  # Reserve every backup destination before the first output mutation. mktemp
  # creates the placeholder; mv atomically replaces it when preserving an
  # existing output. Tracking placeholders in temps makes allocation failure
  # clean without requiring rollback because no output has changed yet.
  for index in "${!staged_outputs[@]}"; do
    output=${staged_outputs[$index]}
    backup=""
    if [ -e "$output" ] || [ -L "$output" ]; then
      backup=$(mktemp "$(dirname "$output")/.config-backup.XXXXXX")
      temps+=("$backup")
    fi
    backups[$index]="$backup"
  done

  rollback_prior() {
    local last=$1 rollback prior_backup
    for ((rollback=last; rollback >= 0; rollback--)); do
      rm -f "${staged_outputs[$rollback]}" || true
      prior_backup=${backups[$rollback]:-}
      if [ -n "$prior_backup" ]; then
        mv "$prior_backup" "${staged_outputs[$rollback]}" || warn "warning: failed to restore ${staged_outputs[$rollback]}"
      fi
    done
  }
  for index in "${!staged_sources[@]}"; do
    output=${staged_outputs[$index]}; backup=${backups[$index]:-}
    if [ -n "$backup" ]; then
      if ! mv "$output" "$backup"; then
        rollback_prior "$((index - 1))"
        exit 1
      fi
    fi
    backups[$index]="$backup"
    if ! mv "${staged_sources[$index]}" "$output"; then
      [ -z "$backup" ] || mv "$backup" "$output" || warn "warning: failed to restore $output"
      rollback_prior "$((index - 1))"
      exit 1
    fi
  done
  for backup in "${backups[@]}"; do
    [ -z "$backup" ] || rm -f "$backup" || warn "warning: failed to remove backup $backup"
  done
  for output in "${staged_outputs[@]}"; do printf 'assembled -> %s\n' "$output" || true; done
fi
exit "$drift"
