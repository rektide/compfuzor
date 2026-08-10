set -euo pipefail

: "${BACKUP_ROOT:={{BACKUP_TARGET}}}"
DATA_SRC="${HOME}/.local/share/opencode"
DATA_DST="${BACKUP_ROOT}/opencode"
CONFIG_SRC="${HOME}/.config/opencode"
CONFIG_DST="${BACKUP_ROOT}/opencode-config"

SCRIPT_NAME="${0##*/}"

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Mirror opencode user data to ${BACKUP_ROOT}/.

Options:
  -n, --dry-run    Show what would transfer without writing anything.
      --config     Also mirror ~/.config/opencode/ to ${CONFIG_DST}/
                   (skills, prompts, opencode.json, memory-banks).
      --db-only    Mirror only root SQLite DB and auth files. Much faster
                   (seconds) for mid-session refreshes. Destination keeps
                   all other existing content.
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
  local dry_run="$1"
  local label="$2"
  local completion="complete"
  local rc=0
  shift 2

  if [ "$dry_run" = 1 ]; then completion="dry run complete"; fi
  log "starting ${label}"
  rsync "$@" || rc=$?
  case "$rc" in
    0)  log "${label} ${completion}" ;;
    24) log "${label} ${completion} with warnings (rsync 24: some source files vanished during copy - usually benign for live backups)" ;;
    *)  printf 'error: rsync failed with code %d during %s\n' "$rc" "$label" >&2; exit "$rc" ;;
  esac
}

guard_destination() {
  local destination="$1"
  local destination_real
  local source
  local source_real
  shift

  destination_real="$(realpath -m -- "$destination")"
  for source in "$@"; do
    source_real="$(realpath -e -- "$source")"
    case "$destination_real" in
      "$source_real"|"$source_real"/*)
        printf 'error: backup destination must not equal or be inside a source: %s\n' "$destination" >&2
        exit 1
        ;;
    esac
  done
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

  case "$BACKUP_ROOT" in
    /*) ;;
    *) printf 'error: BACKUP_ROOT must be an absolute path: %s\n' "$BACKUP_ROOT" >&2; exit 1 ;;
  esac

  for d in "$DATA_SRC" "$BACKUP_ROOT"; do
    if [ ! -d "$d" ]; then
      printf 'error: required directory missing: %s\n' "$d" >&2
      exit 1
    fi
  done

  if [ "$include_config" = 1 ] && [ ! -d "$CONFIG_SRC" ]; then
    printf 'error: --config requested but %s missing\n' "$CONFIG_SRC" >&2
    exit 1
  fi

  local sources=("$DATA_SRC")
  if [ -d "$CONFIG_SRC" ]; then sources+=("$CONFIG_SRC"); fi
  guard_destination "$DATA_DST" "${sources[@]}"
  if [ "$include_config" = 1 ]; then
    guard_destination "$CONFIG_DST" "${sources[@]}"
  fi

  local common_args=(-a --delete --modify-window=1 --exclude='*.v2ed*' --stats --partial-dir=.rsync-partial --no-whole-file --block-size=65536)
  if [ "$verbose" = 1 ]; then common_args+=(-v); fi
  if [ -t 2 ]; then common_args+=(--info=progress2); fi
  if [ "$dry_run" = 1 ]; then common_args+=(--dry-run); fi

  local data_args=("${common_args[@]}")
  if [ "$db_only" = 1 ]; then
    data_args+=(
      --include='/auth*.json*'
      --include='/db.sqlite*'
      --include='/*.db*'
      --exclude='/*'
    )
  fi

  local config_args=("${common_args[@]}" --exclude='node_modules/')

  if pgrep -x opencode >/dev/null 2>&1; then
    log "warning: opencode is running; the live DB may be captured mid-write. For a guaranteed-clean snapshot, quit opencode first."
  fi

  run_rsync "$dry_run" "data mirror: ${DATA_SRC}/ -> ${DATA_DST}/" \
    "${data_args[@]}" -- "${DATA_SRC}/" "${DATA_DST}/"

  if [ "$include_config" = 1 ]; then
    run_rsync "$dry_run" "config mirror: ${CONFIG_SRC}/ -> ${CONFIG_DST}/" \
      "${config_args[@]}" -- "${CONFIG_SRC}/" "${CONFIG_DST}/"
  fi

  if [ "$dry_run" = 1 ]; then
    log "dry run done"
  else
    log "done"
  fi
}

main "$@"
