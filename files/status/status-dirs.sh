# status-dirs.sh — dump key/value contents of declared directories.
#
# Generic read-only dumper: for each declared directory, list its one-level
# files and print them split as dir, key (filename), value. Used to surface
# live state from /proc, /sys, debugfs, etc. that has no declared "desired"
# form (the three-way status-*.ts tools handle managed keys with drift; this
# is just "show me what's in these dirs"). It generalizes the hand-rolled
# show_dir() in the zswap/pstore bins.
#
# Source of truth: the env vars STATUS_DIRS and STATUS_DIRS_SUDO, each a
# colon-separated list of directories (PATH-style). Two lists because some trees
# need root to read:
#   STATUS_DIRS       read as the invoking user
#   STATUS_DIRS_SUDO  read via sudo (e.g. /sys/kernel/debug/*)
# Set either, or both. Missing/unreadable directories are skipped; the run
# fails (exit 1) only if nothing at all was printed. --dir/--sudo-dir flags
# append to the env lists (useful for one-off runs and tests).
#
# This is a compfuzor _bin body: files/_bin supplies the shebang,
# `set -euo pipefail`, env loading, and option restoration.
#
# Output: TSV `dir\tkey\tvalue` by default (with header); --json emits one
# object {dir,key,value} per line (JSON Lines); --json-array emits a single
# JSON array. Values have a single trailing newline trimmed.
#
# Exit: 0 if anything was printed, 1 if nothing found, 2 usage error.

# run a command with or without sudo depending on $USE_SUDO (avoids the
# empty-leading-arg problem of an unquoted $SUDO)
run() { if [ "$USE_SUDO" = 1 ]; then sudo "$@"; else "$@"; fi; }

# parallel arrays: DIRS[i] read with SUDO_FLAG[i] (0=user, 1=sudo)
DIRS=()
SUDO_FLAG=()

# env is the source of truth (colon-separated, like PATH); empty entries skipped
IFS=: read -r -a _non_sudo <<< "${STATUS_DIRS:-}"
IFS=: read -r -a _sudo     <<< "${STATUS_DIRS_SUDO:-}"
for d in "${_non_sudo[@]:-}"; do [ -n "$d" ] && { DIRS+=("$d"); SUDO_FLAG+=(0); }; done
for d in "${_sudo[@]:-}";     do [ -n "$d" ] && { DIRS+=("$d"); SUDO_FLAG+=(1); }; done

FORMAT=tsv
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      cat >&2 <<'EOF'
usage: status-dirs.sh [--json | --json-array] [--dir DIR]... [--sudo-dir DIR]...
  Dump one-level file contents of declared directories as dir<TAB>key<TAB>value.
  Sources (env, whitespace-separated): STATUS_DIRS, STATUS_DIRS_SUDO.
  --dir DIR        user-readable directory (repeatable; appends to STATUS_DIRS)
  --sudo-dir DIR   directory read via sudo (repeatable; appends to STATUS_DIRS_SUDO)
  --json           one JSON object per row (JSON Lines)
  --json-array     all rows as a single JSON array
EOF
      exit 0 ;;
    --json) FORMAT=jsonl; shift ;;
    --json-array) FORMAT=array; shift ;;
    --dir) DIRS+=("${2:?--dir needs a path}"); SUDO_FLAG+=(0); shift 2 ;;
    --sudo-dir) DIRS+=("${2:?--sudo-dir needs a path}"); SUDO_FLAG+=(1); shift 2 ;;
    *) printf 'status-dirs.sh: unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# dump each directory: list (root-visible if sudo), cat each regular file
LINES=()
for i in "${!DIRS[@]}"; do
  dir="${DIRS[$i]}"
  USE_SUDO="${SUDO_FLAG[$i]}"
  entries=$(run ls -1 "$dir" 2>/dev/null) || continue   # missing/inaccessible dir -> skip
  [ -n "$entries" ] || continue
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    run test -f "$dir/$f" 2>/dev/null || continue        # skip subdirs
    val=$(run cat "$dir/$f" 2>/dev/null) || val="<error>" # some sysfs files EIO on read
    val="${val%$'\n'}"                                    # trim one trailing newline
    LINES+=("$dir"$'\t'"$f"$'\t'"$val")
  done <<< "$entries"
done

# nothing found at all -> fail
if [ "${#LINES[@]}" -eq 0 ]; then
  exit 1
fi

case "$FORMAT" in
  tsv)
    printf 'dir\tkey\tvalue\n'
    printf '%s\n' "${LINES[@]}" ;;
  jsonl)
    printf '%s\n' "${LINES[@]}" \
      | while IFS=$'\t' read -r d k v; do jq -cn --arg d "$d" --arg k "$k" --arg v "$v" '{dir:$d,key:$k,value:$v}'; done ;;
  array)
    printf '%s\n' "${LINES[@]}" \
      | jq -Rn '[inputs | split("\t") | {dir:.[0], key:.[1], value:.[2]}]' ;;
esac

exit 0
