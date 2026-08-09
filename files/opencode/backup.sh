set -euo pipefail

: "${BACKUP_ROOT:={{BACKUP_TARGET}}}"
DATA_SRC="${HOME}/.local/share/opencode"
DATA_DST="${BACKUP_ROOT}/opencode"
CONFIG_SRC="${HOME}/.config/opencode"
CONFIG_DST="${BACKUP_ROOT}/opencode-config"

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Mirror opencode user data to ${BACKUP_ROOT}/.

Options:
  -n, --dry-run    Show what would transfer without writing anything.
      --config     Also mirror ~/.config/opencode/ to ${CONFIG_DST}/
                   (skills, prompts, opencode.json, memory-banks).
      --db-only    Skip storage/, snapshot/, bin/, log/, tool-output/,
                   repos/, shell/, project/ - mirrors only the SQLite
                   DBs and auth files. Much faster (seconds) for
                   mid-session refreshes. Destination keeps existing
                   excluded content.
  -v, --verbose    Verbose rsync output (per-file list).
  -h, --help       Show this help.

Default (no flags): mirrors ${DATA_SRC}/ to ${DATA_DST}/
with --delete and NTFS-safe flags. --block-size=65536 balances
delta-transfer granularity against protocol overhead.
--partial-dir=.rsync-partial makes transfers resumable across kills.
Excludes *.v2ed* migration artifacts.

BACKUP_ROOT env var overrides the destination root (default:
{{BACKUP_TARGET}}).
EOF
}

log() { printf '[%(%Y-%m-%dT%H:%M:%S)T] %s\n' -1 "$*"; }

run_rsync() {
  local label="$1"; shift
  log "starting ${label}"
  set +e
  rsync "$@"
  local rc=$?
  set -e
  case "$rc" in
    0)  log "${label} complete" ;;
    24) log "${label} complete with warnings (rsync 24: some source files vanished during copy - usually benign for live backups)" ;;
    *)  printf 'error: rsync failed with code %d during %s\n' "$rc" "$label" >&2; exit "$rc" ;;
  esac
}

main() {
  local dry_run=0
  local include_config=0
  local db_only=0
  local verbose=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -n|--dry-run) dry_run=1; shift ;;
      --config) include_config=1; shift ;;
      --db-only) db_only=1; shift ;;
      -v|--verbose) verbose=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
  done

  for d in "$DATA_SRC" "$BACKUP_ROOT"; do
    if [ ! -d "$d" ]; then
      printf 'error: required directory missing: %s\n' "$d" >&2
      exit 1
    fi
  done

  local rsync_args=(-a --delete --modify-window=1 --exclude='*.v2ed*' --stats --partial-dir=.rsync-partial --no-whole-file --block-size=65536)
  if [ "$verbose" = 1 ]; then rsync_args+=(-v); fi
  if [ -t 2 ]; then rsync_args+=(--info=progress2); fi
  if [ "$dry_run" = 1 ]; then rsync_args+=(--dry-run); fi
  if [ "$db_only" = 1 ]; then
    rsync_args+=(
      --exclude='storage/'
      --exclude='snapshot/'
      --exclude='bin/'
      --exclude='log/'
      --exclude='tool-output/'
      --exclude='repos/'
      --exclude='shell/'
      --exclude='project/'
    )
  fi

  if pgrep -x opencode >/dev/null 2>&1; then
    log "warning: opencode is running; the live DB may be captured mid-write. For a guaranteed-clean snapshot, quit opencode first."
  fi

  run_rsync "data mirror: ${DATA_SRC}/ -> ${DATA_DST}/" \
    "${rsync_args[@]}" "${DATA_SRC}/" "${DATA_DST}/"

  if [ "$include_config" = 1 ]; then
    if [ ! -d "$CONFIG_SRC" ]; then
      printf 'error: --config requested but %s missing\n' "$CONFIG_SRC" >&2
      exit 1
    fi
    run_rsync "config mirror: ${CONFIG_SRC}/ -> ${CONFIG_DST}/" \
      "${rsync_args[@]}" --exclude='node_modules/' "${CONFIG_SRC}/" "${CONFIG_DST}/"
  fi

  log "done"
}

main "$@"
