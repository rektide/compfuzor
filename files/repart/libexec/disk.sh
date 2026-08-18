#!/bin/bash
set -euo pipefail

die() { printf 'repart disk: error: %s\n' "$*" >&2; exit 2; }
note() { printf 'repart disk: %s\n' "$*" >&2; }
self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$self/../.." && pwd)"
profile="$self/profile.sh"

canonical() { realpath -e -- "$1" 2>/dev/null || die "target does not exist: $1"; }
fingerprint() {
  identity="$(stat -Lc '%F|dev=%d|inode=%i|rdev=%t:%T|size=%s' -- "$1")"
  block="$(lsblk -dnro MAJ:MIN,SIZE,SERIAL,WWN,MODEL "$1" 2>/dev/null || true)"
  table="$(sfdisk --dump "$1" 2>/dev/null | sha256sum | awk '{print $1}')"
  printf '%s|block=%s|table=%s\n' "$identity" "$block" "$table"
}
plan_digest() {
  (cd "$1" && {
    sha256sum plan arguments
    while IFS= read -r -d '' file; do sha256sum "$file"; done \
      < <(find definitions -type f -print0 | sort -z)
  } | sha256sum | awk '{print $1}')
}
version() { systemd-repart --version 2>/dev/null | awk 'NR==1 { print $2 }'; }
check_migrate_source() {
  [ "$(stat -f -c %T "$1")" = btrfs ] || die "migration source is not btrfs: $1"
  count="$(btrfs filesystem show "$1" 2>/dev/null | awk '/devid/{n++} END{print n+0}')"
  [ "$count" = 1 ] || die "migration source must be single-device btrfs (found $count)"
  ver="$(version)"; case "$ver" in ''|*[!0-9]*) die "cannot parse systemd-repart version" ;; esac
  [ "$ver" -ge 261 ] || die "migration requires systemd-repart >=261 (found $ver)"
}
reject_mounted() {
  devices=("$1")
  if [ -f "$1" ]; then
    while IFS= read -r loop; do [ -z "$loop" ] || devices+=("$loop"); done < <(losetup -j "$1" -O NAME -n 2>/dev/null || true)
  fi
  for root_device in "${devices[@]}"; do
    while read -r dev; do
      [ -n "$dev" ] || continue
      if findmnt -rn -S "$dev" >/dev/null 2>&1; then die "target or target partition is mounted: $dev"; fi
    done < <(lsblk -nrpo NAME "$root_device" 2>/dev/null || printf '%s\n' "$root_device")
  done
}

command="${1:-}"; shift || true
case "$command" in
  plan)
    operation="${1:-}"; shift || true
    case "$operation" in format|migrate) ;; *) die "usage: repart disk plan {format TARGET|migrate TARGET --source MOUNT} [profile options]" ;; esac
    [ $# -gt 0 ] || die "$operation needs TARGET"
    target="$(canonical "$1")"; shift
    source=""; profile_args=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --source) [ "$operation" = migrate ] || die "--source is only valid for migrate"; source="$(realpath -e "${2:?--source needs MOUNT}")"; shift 2 ;;
        --base|--overlay|--date|--arch|--swap|--set) profile_args+=("$1" "${2:?$1 needs a value}"); shift 2 ;;
        -*) die "unknown option (raw repart passthrough is forbidden): $1" ;;
        *) die "unexpected argument: $1" ;;
      esac
    done
    if [ "$operation" = migrate ]; then [ -n "$source" ] || die "migrate requires --source MOUNT"; check_migrate_source "$source"; fi
    flavor_name="$operation"; [ "$operation" != migrate ] || flavor_name=bdr
    base="$root/etc/defs/universal.d"; flavor="$root/etc/defs/$flavor_name.d"
    # Source-tree execution uses files/repart/defs; installed execution uses etc/defs.
    if [ ! -d "$base" ]; then base="$self/../defs/universal.d"; flavor="$self/../defs/$flavor_name.d"; fi
    if [ ! -d "$base" ] || [ ! -d "$flavor" ]; then die "canonical $operation definitions are not installed"; fi
    render_args=(render --base "$base")
    # User overlays refine the base but the operation flavor is always final.
    for ((i=0; i<${#profile_args[@]}; i+=2)); do
      if [ "${profile_args[$i]}" != --base ]; then render_args+=("${profile_args[$i]}" "${profile_args[$((i+1))]}");
      else render_args[2]="${profile_args[$((i+1))]}"; fi
    done
    render_args+=(--overlay "$flavor")
    [ "$operation" = migrate ] && render_args+=(--set "SOURCE=$source")
    defs="$($profile "${render_args[@]}")"
    plan="$(mktemp -d "${REPART_SCRATCH:-/var/tmp}/repart-plan.XXXXXX")"
    trap 'rm -rf "$plan" "$defs"' ERR INT TERM
    mv "$defs" "$plan/definitions"
    {
      printf 'operation=%s\n' "$operation"
      printf 'target=%s\n' "$target"
      printf 'source=%s\n' "$source"
      printf 'fingerprint=%s\n' "$(fingerprint "$target")"
    } >"$plan/plan"
    if [ "$operation" = format ]; then printf '%s\n' --offline=yes --empty=force --dry-run=yes >"$plan/arguments";
    else printf '%s\n' --empty=force --dry-run=yes >"$plan/arguments"; fi
    plan_digest "$plan" >"$plan/digest"
    mapfile -t args <"$plan/arguments"
    note "dry-run $operation plan for $target"
    systemd-repart --definitions="$plan/definitions" "${args[@]}" "$target" >&2
    trap - ERR INT TERM
    plan="$(realpath "$plan")"
    note "persisted plan at $plan"
    printf '%s\n' "$plan"
    ;;
  apply)
    if [ $# -lt 3 ] || [ "$2" != --confirm ]; then die "usage: repart disk apply PLAN --confirm TARGET"; fi
    plan="$(realpath -e "$1")"; confirmed="$(canonical "$3")"; [ $# -eq 3 ] || die "unexpected apply arguments"
    if [ ! -f "$plan/plan" ] || [ ! -d "$plan/definitions" ] || [ ! -f "$plan/arguments" ] || [ ! -f "$plan/digest" ]; then
      die "invalid plan directory: $plan"
    fi
    [ "$(plan_digest "$plan")" = "$(cat "$plan/digest")" ] || die "plan contents changed after preview"
    operation=""; target=""; source=""; saved_fingerprint=""
    while IFS='=' read -r key value; do case "$key" in operation) operation="$value" ;; target) target="$value" ;; source) source="$value" ;; fingerprint) saved_fingerprint="$value" ;; esac; done <"$plan/plan"
    case "$operation" in
      format) expected=(--offline=yes --empty=force --dry-run=yes) ;;
      migrate) expected=(--empty=force --dry-run=yes) ;;
      *) die "invalid planned operation: $operation" ;;
    esac
    mapfile -t args <"$plan/arguments"
    [ "${args[*]}" = "${expected[*]}" ] || die "plan contains invalid repart arguments"
    [ "$confirmed" = "$target" ] || die "confirmation target differs from planned target ($confirmed != $target)"
    [ "$(fingerprint "$target")" = "$saved_fingerprint" ] || die "target identity/fingerprint changed since planning"
    reject_mounted "$target"
    [ "$operation" != migrate ] || check_migrate_source "$source"
    for i in "${!args[@]}"; do [ "${args[i]}" != --dry-run=yes ] || args[i]=--dry-run=no; done
    note "applying persisted $operation plan to $target; plan retained at $plan"
    systemd-repart --definitions="$plan/definitions" "${args[@]}" "$target" >&2
    ;;
  *) die "usage: repart disk {plan|apply} ..." ;;
esac
