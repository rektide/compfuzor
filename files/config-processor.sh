#!/bin/bash
# Internal config leaf protocol and shared processor implementations.

processor=${1:?processor identity is required}; shift
spec="$DIR/etc/config.spec.json"
: "${CONFIG_TRANSACTION:?config processors are internal; use config.sh [--list | instance/assembly]}"

instance=""; assembly=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --instance) shift; instance=${1:?--instance requires a value} ;;
    --assembly) shift; assembly=${1:?--assembly requires a value} ;;
    -*) printf 'unknown processor option: %s\n' "$1" >&2; exit 2 ;;
    *) printf 'unexpected processor argument: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

[ -n "$instance" ] && [ -n "$assembly" ] || {
  printf 'transactional leaf invocation requires explicit --instance and --assembly\n' >&2; exit 2;
}
: "${CONFIG_CANDIDATE:?CONFIG_CANDIDATE is required}"
: "${CONFIG_INPUTS_FILE:?CONFIG_INPUTS_FILE is required}"
expected=$(jq -r --arg i "$instance" --arg a "$assembly" '.configs[$i].assemblies[$a].processor // empty' "$spec")
[ "$expected" = "$processor" ] || { printf '%s/%s does not use processor %s\n' "$instance" "$assembly" "$processor" >&2; exit 2; }

case "$processor" in
  concat)
    : > "$CONFIG_CANDIDATE"
    while IFS=$'\t' read -r _kind _identity path _block; do cat "$path" >> "$CONFIG_CANDIDATE"; done < "$CONFIG_INPUTS_FILE"
    ;;
  json-deep-merge)
    files=()
    while IFS=$'\t' read -r _kind _identity path _block; do files+=("$path"); done < "$CONFIG_INPUTS_FILE"
    if [ "${{ '{#' }}files[@]}" -eq 0 ]; then printf '{}\n' > "$CONFIG_CANDIDATE"; else jq -s 'reduce .[] as $item ({}; . * $item)' "${files[@]}" > "$CONFIG_CANDIDATE"; fi
    ;;
  block-in-file)
    output=$(jq -r --arg i "$instance" --arg a "$assembly" '.configs[$i].assemblies[$a].output' "$spec")
    namespace=$(jq -r --arg i "$instance" --arg a "$assembly" '.configs[$i].assemblies[$a].block.namespace' "$spec")
    if [ -f "$output" ]; then cp "$output" "$CONFIG_CANDIDATE"; else : > "$CONFIG_CANDIDATE"; fi
    command=${CONFIG_BLOCK_IN_FILE:-block-in-file}
    escaped=$(printf '%s' "$namespace" | sed 's/[][\\.^$*+?(){}|]/\\&/g')
    removal_error=$(mktemp)
    if ! "$command" --remove-match "^${escaped}/" -o "$CONFIG_CANDIDATE" 2>"$removal_error"; then
      printf 'block-in-file command lacks required --remove-match support: %s\n' "$command" >&2
      cat "$removal_error" >&2
      rm -f "$removal_error"
      exit 2
    fi
    rm -f "$removal_error"
    while IFS= read -r pattern; do
      "$command" --remove-match "$pattern" -o "$CONFIG_CANDIDATE"
    done < <(jq -r --arg i "$instance" --arg a "$assembly" '.configs[$i].assemblies[$a].block.remove_match[]?' "$spec")
    while IFS=$'\t' read -r _kind identity path block; do
      args=(-n "$namespace/$identity" -i "$path" -o "$CONFIG_CANDIDATE")
      for placement in before after anchor; do
        value=$(jq -r --arg key "$placement" '.[$key] // empty' <<<"$block")
        [ -z "$value" ] || args+=("--$placement" "$value")
      done
      "$command" "${args[@]}"
    done < "$CONFIG_INPUTS_FILE"
    ;;
  *) printf 'unsupported config processor: %s\n' "$processor" >&2; exit 2 ;;
esac
