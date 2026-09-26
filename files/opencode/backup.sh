set -euo pipefail

# Mirror opencode user state to one or more backup targets.
#
# Targets come space-separated from BACKUP_TARGETS (rendered default below);
# BACKUP_ROOT overrides with a single target for ad-hoc runs. A missing or
# unmounted target is skipped with a warning (autofs/CIFS targets come and
# go) but still fails the run overall.
#
# TODO(btrfs): version the mirrors over time with btrfs snapshots instead of
# bare rsync --delete, which overwrites the only copy of each DB generation.
#   pre-run, per target:  btrfs subvolume snapshot -r <target>/opencode \
#                           <target>/opencode@$(date -u +%Y%m%dT%H%M%SZ)
#   post-run:             prune snapshots past a count/age retention policy
# COW snapshots make keeping every pre-rsync DB generation cheap, so a
# corrupted live DB can never clobber the last good backup. Constraint found
# 2026-09-26: /mnt/fu is NTFS (fuseblk) and /mnt/bitblaster is CIFS, so
# neither current target supports host-side btrfs snapshots — this needs a
# btrfs target (or snapshots taken on the backing server). Until then the
# versioning pattern is dated consistent-snapshot-<stamp>/ dirs made with
# sqlite3 .backup + integrity_check + sha256 (see
# consistent-snapshot-20260923T185710/ on the fu target).
: "${BACKUP_TARGETS:={{ BACKUP_TARGETS|join(' ') }}}"
if [ -n "${BACKUP_ROOT:-}" ]; then
  BACKUP_TARGETS="$BACKUP_ROOT"
fi
DATA_SRC="${HOME}/.local/share/opencode"
CONFIG_SRC="${HOME}/.config/opencode"

SCRIPT_NAME="${0##*/}"

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Mirror opencode user data to every configured backup target
(space-separated; default: {{ BACKUP_TARGETS|join(' ') }}).

Options:
  -n, --dry-run    Show what would transfer without writing anything.
      --config     Also mirror ~/.config/opencode/ to
                   <target>/opencode-config/ (skills, prompts,
                   opencode.json, memory-banks).
      --db-only    Mirror only root SQLite DB and auth files. Much faster
                   (seconds) for mid-session refreshes. Destination keeps
                   all other existing content.
  -v, --verbose    Verbose rsync output (per-file list).
  -h, --help       Show this help.

Default (no flags): mirrors ${DATA_SRC}/ to <target>/opencode/ of each
target with --delete and NTFS/CIFS-safe flags (both filesystems have coarse
mtime granularity). --block-size=65536 balances delta-transfer granularity
against protocol overhead. --partial-dir=.rsync-partial makes transfers
resumable across kills. Excludes *.v2ed* migration artifacts.

BACKUP_TARGETS env var overrides the target list (space-separated);
BACKUP_ROOT overrides with a single target.
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

  if [ ! -d "$DATA_SRC" ]; then
    printf 'error: required directory missing: %s\n' "$DATA_SRC" >&2
    exit 1
  fi

  # A source checkout must never be mirrored over backup targets: a checkout
  # copied into /mnt/fu/backup/opencode-2026-5 is exactly the pollution that
  # required a manual cleanup. ~/.local/share/opencode is user state only.
  if [ -e "${DATA_SRC}/.git" ] || { [ -f "${DATA_SRC}/package.json" ] && [ -f "${DATA_SRC}/bun.lock" ]; }; then
    printf 'error: %s looks like a source checkout (.git / package.json+bun.lock); refusing to mirror it over backup targets\n' "$DATA_SRC" >&2
    exit 1
  fi

  if [ "$include_config" = 1 ] && [ ! -d "$CONFIG_SRC" ]; then
    printf 'error: --config requested but %s missing\n' "$CONFIG_SRC" >&2
    exit 1
  fi

  local targets=()
  read -ra targets <<<"${BACKUP_TARGETS}"
  if [ -z "${targets[*]:-}" ]; then
    printf 'error: no backup targets configured (BACKUP_TARGETS is empty)\n' >&2
    exit 1
  fi

  local common_args=(-a --delete --modify-window=2 --exclude='*.v2ed*' --stats --partial-dir=.rsync-partial --no-whole-file --block-size=65536)
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

  local sources=("$DATA_SRC")
  if [ -d "$CONFIG_SRC" ]; then sources+=("$CONFIG_SRC"); fi

  local failures=0
  local total=0
  local target data_dst config_dst
  for target in "${targets[@]}"; do
    total=$((total + 1))
    data_dst="${target%/}/opencode"
    config_dst="${target%/}/opencode-config"
    if [ ! -d "$target" ]; then
      log "warning: backup target missing or unmounted, skipping: ${target}"
      failures=$((failures + 1))
      continue
    fi
    guard_destination "$data_dst" "${sources[@]}"
    if [ "$include_config" = 1 ]; then
      guard_destination "$config_dst" "${sources[@]}"
    fi
    run_rsync "$dry_run" "data mirror: ${DATA_SRC}/ -> ${data_dst}/" \
      "${data_args[@]}" -- "${DATA_SRC}/" "${data_dst}/"
    if [ "$include_config" = 1 ]; then
      run_rsync "$dry_run" "config mirror: ${CONFIG_SRC}/ -> ${config_dst}/" \
        "${config_args[@]}" -- "${CONFIG_SRC}/" "${config_dst}/"
    fi
  done

  if [ "$failures" -gt 0 ]; then
    printf 'error: %d of %d backup targets were missing or unmounted\n' "$failures" "$total" >&2
    exit 1
  fi

  if [ "$dry_run" = 1 ]; then
    log "dry run done"
  else
    log "done"
  fi
}

main "$@"
