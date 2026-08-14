set -euo pipefail
shopt -s nullglob

readonly OPENTUI_SIZE=13745312
readonly OPENTUI_SHA256=ce73133a58d35e35610ef53353ddeeeb93fb29505dde0cf1854ce25facee241d
readonly FFF_SIZE=12559952
readonly FFF_SHA256=745e5a94424e3d9893eaea5f471846f1e4e4baa5dad1a5af47acaeea09bae

script_name=${0##*/}
tmp_dir=${TMPDIR:-/tmp}
min_age=24h
apply=0
require_no_opencode=0

usage() {
  cat <<EOF
Usage: $script_name [options]

Find leaked OpenCode OpenTUI/FFF native libraries directly under /tmp.
The default is a dry run; deletion requires --apply.

Options:
      --apply                 Delete eligible files.
      --min-age DURATION      Minimum age (default: 24h). Suffix: s, m, h, d.
      --require-no-opencode   Refuse to run while opencode/opencode2 exists.
      --tmp-dir DIR           Inspect DIR instead of TMPDIR or /tmp (testing).
  -h, --help                  Show this help.

Eligibility requires an exact known filename shape, byte size, SHA-256 digest,
owner, link count, age, and inactive status. /tmp/opencode is never traversed.
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

parse_duration() {
  local value=$1
  local number suffix multiplier
  if [[ ! $value =~ ^([0-9]+)([smhd])$ ]]; then
    fail "invalid duration '$value' (expected an integer followed by s, m, h, or d)"
  fi
  number=${BASH_REMATCH[1]}
  suffix=${BASH_REMATCH[2]}
  case $suffix in
    s) multiplier=1 ;;
    m) multiplier=60 ;;
    h) multiplier=3600 ;;
    d) multiplier=86400 ;;
  esac
  printf '%s\n' "$((number * multiplier))"
}

human_bytes() {
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B "$1"
  else
    printf '%sB\n' "$1"
  fi
}

snapshot() {
  # Include nanosecond mtime/ctime text in the identity used for race checks.
  stat -c '%d|%i|%u|%h|%s|%Y|%b|%y|%z' -- "$1" 2>/dev/null
}

declare -A active_paths=()

record_active_paths() {
  local maps fd target
  for maps in /proc/[0-9]*/maps; do
    while IFS= read -r target; do
      target=${target% (deleted)}
      [[ $target == /* ]] && active_paths["$target"]=1
    done < <(awk '$NF ~ /^\// { print $NF }' "$maps" 2>/dev/null || true)
  done
  for fd in /proc/[0-9]*/fd/*; do
    target=$(readlink -- "$fd" 2>/dev/null) || continue
    target=${target% (deleted)}
    [[ $target == /* ]] && active_paths["$target"]=1
  done
}

is_active_now() {
  local path=$1
  local maps fd target
  if command -v fuser >/dev/null 2>&1 && fuser -s -- "$path" 2>/dev/null; then
    return 0
  fi
  if grep -Fql -- "$path" /proc/[0-9]*/maps 2>/dev/null; then
    return 0
  fi
  if ! command -v fuser >/dev/null 2>&1; then
    for fd in /proc/[0-9]*/fd/*; do
      target=$(readlink -- "$fd" 2>/dev/null) || continue
      [[ ${target% (deleted)} == "$path" ]] && return 0
    done
  fi
  return 1
}

while (($#)); do
  case $1 in
    --apply)
      apply=1
      shift
      ;;
    --min-age)
      (($# >= 2)) || fail '--min-age requires a duration'
      min_age=$2
      shift 2
      ;;
    --require-no-opencode)
      require_no_opencode=1
      shift
      ;;
    --tmp-dir)
      (($# >= 2)) || fail '--tmp-dir requires a directory'
      tmp_dir=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

min_age_seconds=$(parse_duration "$min_age")
[[ -d $tmp_dir ]] || fail "temporary directory does not exist: $tmp_dir"
tmp_dir=$(realpath -e -- "$tmp_dir")
[[ $tmp_dir != / ]] || fail 'refusing to inspect the filesystem root'

if ((require_no_opencode)) &&
  (pgrep -x opencode >/dev/null 2>&1 || pgrep -x opencode2 >/dev/null 2>&1); then
  fail 'OpenCode processes are running (--require-no-opencode)'
fi

record_active_paths

now=$(date +%s)
cutoff=$((now - min_age_seconds))
uid=$(id -u)
scanned=0
eligible=0
deleted=0
eligible_bytes=0
deleted_bytes=0
skipped_young=0
skipped_active=0
skipped_identity=0
skipped_content=0
skipped_changed=0

while IFS= read -r -d '' path; do
  name=${path##*/}
  [[ $name =~ ^\.[0-9a-f]+-0000000(0|2)\.so$ ]] || continue
  ((scanned += 1))

  [[ ! -L $path ]] || { ((skipped_identity += 1)); continue; }
  before=$(snapshot "$path") || { ((skipped_changed += 1)); continue; }
  IFS='|' read -r _ inode owner links size mtime blocks _ _ <<<"$before"

  if [[ $owner != "$uid" || $links != 1 ]]; then
    ((skipped_identity += 1))
    continue
  fi
  if ((mtime > cutoff)); then
    ((skipped_young += 1))
    continue
  fi
  case $size in
    "$OPENTUI_SIZE") expected_hash=$OPENTUI_SHA256 ;;
    "$FFF_SIZE") expected_hash=$FFF_SHA256 ;;
    *) ((skipped_content += 1)); continue ;;
  esac
  if [[ -n ${active_paths[$path]+x} ]]; then
    ((skipped_active += 1))
    continue
  fi

  hash_line=$(sha256sum -- "$path") || { ((skipped_changed += 1)); continue; }
  hash=${hash_line%% *}
  if [[ $hash != "$expected_hash" ]]; then
    ((skipped_content += 1))
    printf 'skip content mismatch: %q\n' "$path" >&2
    continue
  fi
  after_hash=$(snapshot "$path") || { ((skipped_changed += 1)); continue; }
  if [[ $after_hash != "$before" ]]; then
    ((skipped_changed += 1))
    continue
  fi

  allocated=$((blocks * 512))
  ((eligible += 1))
  ((eligible_bytes += allocated))

  if ((!apply)); then
    printf 'eligible age=%ss allocated=%s inode=%s path=%q\n' \
      "$((now - mtime))" "$(human_bytes "$allocated")" "$inode" "$path"
    continue
  fi

  if is_active_now "$path"; then
    ((skipped_active += 1))
    ((eligible -= 1))
    ((eligible_bytes -= allocated))
    printf 'skip became active: %q\n' "$path" >&2
    continue
  fi
  before_delete=$(snapshot "$path") || { ((skipped_changed += 1)); continue; }
  if [[ $before_delete != "$before" || -L $path ]]; then
    ((skipped_changed += 1))
    printf 'skip changed before delete: %q\n' "$path" >&2
    continue
  fi
  if rm -- "$path"; then
    ((deleted += 1))
    ((deleted_bytes += allocated))
    printf 'deleted allocated=%s inode=%s path=%q\n' \
      "$(human_bytes "$allocated")" "$inode" "$path"
  else
    ((skipped_changed += 1))
  fi
done < <(find "$tmp_dir" -xdev -mindepth 1 -maxdepth 1 -type f -print0)

mode='dry-run'
((apply)) && mode='apply'
printf '%s summary: scanned=%d eligible=%d eligible_bytes=%s deleted=%d deleted_bytes=%s young=%d active=%d identity=%d content=%d changed=%d\n' \
  "$mode" "$scanned" "$eligible" "$(human_bytes "$eligible_bytes")" \
  "$deleted" "$(human_bytes "$deleted_bytes")" "$skipped_young" \
  "$skipped_active" "$skipped_identity" "$skipped_content" "$skipped_changed"
