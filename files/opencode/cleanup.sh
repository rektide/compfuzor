set -euo pipefail
shopt -s nullglob

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

Eligibility requires an exact known filename shape, ELF identity, owner, link
count, age, and inactive status. /tmp/opencode is never traversed.
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

classify_library() {
  local path=$1
  local name=${path##*/}
  local header metadata

  header=$(readelf --file-header --wide -- "$path" 2>/dev/null) || return 1
  grep -Eq 'Type:[[:space:]]+DYN[[:space:]]' <<<"$header" || return 1

  case $name in
    *-00000000.so)
      metadata=$(readelf --dynamic --wide -- "$path" 2>/dev/null) || return 1
      grep -Fq 'Library soname: [libopentui.so]' <<<"$metadata" || return 1
      printf 'opentui\n'
      ;;
    *-00000002.so)
      metadata=$(readelf --dyn-syms --wide -- "$path" 2>/dev/null) || return 1
      grep -Eq '[[:space:]]fff_search_directories$' <<<"$metadata" || return 1
      grep -Eq '[[:space:]]fff_free_result$' <<<"$metadata" || return 1
      grep -Eq '[[:space:]]fff_file_item_get_file_name$' <<<"$metadata" || return 1
      printf 'fff\n'
      ;;
    *)
      return 1
      ;;
  esac
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
for command_name in awk date find id pgrep readelf realpath rm stat; do
  command -v "$command_name" >/dev/null 2>&1 || fail "required command not found: $command_name"
done
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
  IFS='|' read -r _ inode owner links _ mtime blocks _ _ <<<"$before"

  if [[ $owner != "$uid" || $links != 1 ]]; then
    ((skipped_identity += 1))
    continue
  fi
  if ((mtime > cutoff)); then
    ((skipped_young += 1))
    continue
  fi
  if [[ -n ${active_paths[$path]+x} ]]; then
    ((skipped_active += 1))
    continue
  fi

  if ! library=$(classify_library "$path"); then
    ((skipped_content += 1))
    printf 'skip unrecognized library: %q\n' "$path" >&2
    continue
  fi
  after_inspection=$(snapshot "$path") || { ((skipped_changed += 1)); continue; }
  if [[ $after_inspection != "$before" ]]; then
    ((skipped_changed += 1))
    continue
  fi

  allocated=$((blocks * 512))
  ((eligible += 1))
  ((eligible_bytes += allocated))

  if ((!apply)); then
    printf 'eligible library=%s age=%ss allocated=%s inode=%s path=%q\n' \
      "$library" "$((now - mtime))" "$(human_bytes "$allocated")" "$inode" "$path"
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
    printf 'deleted library=%s allocated=%s inode=%s path=%q\n' \
      "$library" "$(human_bytes "$allocated")" "$inode" "$path"
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
