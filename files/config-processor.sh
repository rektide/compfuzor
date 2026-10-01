#!/bin/bash
# Internal config leaf protocol and shared processor implementations.

processor=${1:?processor identity is required}; shift
spec=${CONFIG_SPEC:-"$DIR/etc/config.spec.json"}
: "${CONFIG_TRANSACTION:?config processors are internal; use config-assemble.sh}"

config=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --config) shift; config=${1:?--config requires a value} ;;
    -*) printf 'unknown processor option: %s\n' "$1" >&2; exit 2 ;;
    *) printf 'unexpected processor argument: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

[ -n "$config" ] || { printf 'transactional leaf invocation requires --config\n' >&2; exit 2; }
: "${CONFIG_CANDIDATE:?CONFIG_CANDIDATE is required}"
: "${CONFIG_INPUTS_FILE:?CONFIG_INPUTS_FILE is required}"
expected=$(jq -r --arg config "$config" '.configs[$config].processor // empty' "$spec")
[ "$expected" = "$processor" ] || { printf '%s does not use processor %s\n' "$config" "$processor" >&2; exit 2; }

case "$processor" in
  concat)
    : > "$CONFIG_CANDIDATE"
    while IFS=$'\t' read -r _kind _identity path _block; do cat "$path" >> "$CONFIG_CANDIDATE"; done < "$CONFIG_INPUTS_FILE"
    ;;
  json-deep-merge)
    printf '{}\n' > "$CONFIG_CANDIDATE"
    while IFS=$'\t' read -r _kind identity path settings; do
      next=$(mktemp "$CONFIG_TRANSACTION/json.XXXXXX") || exit 1
      # Source the explicitly declared producer env in a subshell so each
      # fragment gets its own environment; never leak it into another input.
      (
        env_file=$(jq -r '.envsubst.file // empty' <<<"$settings") || exit 1
        if [ -n "$env_file" ]; then
          case "$env_file" in
            /*) ;;
            *) resolved_source=$(realpath -- "$path") || exit 1
               env_file="$(dirname "$resolved_source")/$env_file" ;;
          esac
          [ -f "$env_file" ] || { printf 'missing JSON input environment file: %s\n' "$env_file" >&2; exit 1; }
          set -a
          # This is a trusted, explicitly declared Compfuzor env.export file.
          source "$env_file" || { printf 'failed to load JSON input environment file: %s\n' "$env_file" >&2; exit 1; }
          set +a
        fi
        jq -s --argjson settings "$settings" --arg identity "$identity" '
          def substitute:
            walk(if type == "string" then
              gsub("\\$\\{(?<key>[A-Za-z_][A-Za-z0-9_]*)\\}";
                env[.key] // error("missing environment variable: " + .key))
            else . end);
          def adapt:
            if type != "object" then .
            else
              (if $settings.place.rename then
                with_entries(if $settings.place.rename[.key] then .key = $settings.place.rename[.key] else . end)
              else . end)
              | if $settings.place.command_args and has("command") then
                  if (.command | type) != "array" then .
                  elif (.command | length) == 0 then error($identity + ": empty command array")
                  else . + {command: .command[0]} + (if (.command | length) > 1 then {args: ((.args // []) + .command[1:])} else {} end)
                  end
                else . end
            end;
          if length != 2 then
            error($identity + ": expected exactly one JSON document in the input")
          else
            .[0] as $base | .[1] as $input |
            (if $settings.envsubst then ($input | substitute) else $input end) |
            (if $settings.place == null then . elif $settings.place.as == "object" then adapt else . end) as $value |
            if $settings.place == null then
              $base * $value
            else
              ($settings.place.at | split(".")) as $path |
              ($base | getpath($path)) as $old |
              if $settings.place.as == "object" then
                if ($value | type) != "object" then error($identity + ": expected JSON object")
                elif $old != null and ($old | type) != "object" then error($identity + ": destination is not an object")
                else
                  ($identity | split("/") | last | sub("\\.json$"; "")) as $slot |
                  if $slot == "" then error($identity + ": empty filename slot")
                  else $base | setpath($path + [$slot]; $value) end
                end
              elif $settings.place.as == "array" then
                if ($value | type) != "array" then error($identity + ": expected JSON array")
                elif $old != null and ($old | type) != "array" then error($identity + ": destination is not an array")
                else $base | setpath($path; ($old // []) + $value) end
              else
                error($identity + ": unsupported placement")
              end
            end
          end
        ' "$CONFIG_CANDIDATE" "$path" > "$next" || exit 1
      ) || { rm -f "$next"; exit 1; }
      mv "$next" "$CONFIG_CANDIDATE" || exit 1
    done < "$CONFIG_INPUTS_FILE"
    ;;
  block-in-file)
    output=$(jq -r --arg config "$config" '.configs[$config].output' "$spec")
    namespace=$(jq -r --arg config "$config" '.configs[$config].block.namespace' "$spec")
    comment=$(jq -r --arg config "$config" '.configs[$config].block.comment // empty' "$spec")
    comment_args=()
    [ -z "$comment" ] || comment_args=(--comment "$comment")
    if [ -f "$output" ]; then cp "$output" "$CONFIG_CANDIDATE"; else : > "$CONFIG_CANDIDATE"; fi
    command=${CONFIG_BLOCK_IN_FILE:-block-in-file}
    escaped=$(printf '%s' "$namespace" | sed 's/[][\\.^$*+?(){}|]/\\&/g')
    removal_error=$(mktemp)
    if ! "$command" "${comment_args[@]}" --remove-match "^${escaped}/" -o "$CONFIG_CANDIDATE" 2>"$removal_error"; then
      printf 'block-in-file command lacks required --remove-match support: %s\n' "$command" >&2
      cat "$removal_error" >&2
      rm -f "$removal_error"
      exit 2
    fi
    rm -f "$removal_error"
    while IFS= read -r pattern; do
      "$command" "${comment_args[@]}" --remove-match "$pattern" -o "$CONFIG_CANDIDATE"
    done < <(jq -r --arg config "$config" '.configs[$config].block.remove_match[]?' "$spec")
    while IFS=$'\t' read -r _kind identity path block; do
      stable=$(jq -r '.id // empty' <<<"$block")
      args=(-n "$namespace/${stable:-$identity}" "${comment_args[@]}" -i "$path" -o "$CONFIG_CANDIDATE")
      for placement in before after anchor; do
        value=$(jq -r --arg key "$placement" '.[$key] // empty' <<<"$block")
        [ -z "$value" ] || args+=("--$placement" "$value")
      done
      "$command" "${args[@]}"
    done < "$CONFIG_INPUTS_FILE"
    ;;
  *) printf 'unsupported config processor: %s\n' "$processor" >&2; exit 2 ;;
esac
