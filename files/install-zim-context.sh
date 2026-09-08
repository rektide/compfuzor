#!/usr/bin/env bash
# Import one producer's Zim fragments into the invoking consumer context.

set -euo pipefail

self_dir="{{DIR}}"
export DIR="$self_dir"
producer=${1:?usage: install-zim-context.sh PRODUCER_DIR}
inputs="$self_dir/bin/config-inputs-user.sh"
assemble="$self_dir/bin/config-user.sh"
builder="$self_dir/bin/zimfw-channel.sh"

[ -x "$inputs" ] || { echo "missing context input tool: $inputs" >&2; exit 2; }
[ -x "$assemble" ] || { echo "missing context assembly tool: $assemble" >&2; exit 2; }
[ -x "$builder" ] || { echo "missing Zim channel builder: $builder" >&2; exit 2; }

channels=()
states=()
sources=()
declare -A seen
declare -A touched
count=0
shopt -s nullglob

# Inventory first so an active/disabled producer conflict cannot partially
# mutate the consumer before it is reported.
for channel_dir in "$producer"/etc/zim/*; do
  [ -d "$channel_dir" ] || continue
  channel=$(basename "$channel_dir")
  case "$channel" in zimrc|zimenv) ;; *) echo "unsupported Zim channel: $channel" >&2; exit 2 ;; esac
  for state in active disabled; do
    for source in "$channel_dir/$state"/*.conf; do
      name=$(basename "$source")
      key="$channel/$name"
      [ -z "${seen[$key]:-}" ] || { echo "producer has both active and disabled entries: $key" >&2; exit 2; }
      seen[$key]=1
      channels+=("$channel")
      states+=("$state")
      sources+=("$source")
    done
  done
done

for index in "${!sources[@]}"; do
  channel=${channels[$index]}
  source=${sources[$index]}
  args=(put "$channel/$channel" "$source" "$(basename "$source")" --strategy link --no-rebuild)
  [ "${states[$index]}" = active ] || args+=(--disabled)
  "$inputs" "${args[@]}"
  touched["$channel"]=1
  count=$((count + 1))
done

# One local assembly and one cache build for each touched channel.
for channel in zimenv zimrc; do
  [ -n "${touched[$channel]:-}" ] || continue
  "$assemble" "$channel"
  "$builder" "$channel" install
done

echo "install-zim-context: imported $count fragment(s) for this consumer"
