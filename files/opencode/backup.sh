set -euo pipefail
shopt -s nullglob

# Mirror opencode user state to one or more backup targets, with optional
# per-run btrfs snapshot versioning and an on-demand consistent-snapshot mode.
#
# Targets are space-separated in BACKUP_TARGETS (rendered default below);
# each entry is a local path or an rsync remote spec (user@host:/path —
# mirrored over ssh; btrfs operations run by ssh'ing into the host).
# BACKUP_ROOT overrides with a single target for ad-hoc runs. A missing or
# unmounted target is skipped with a warning (autofs/CIFS targets come and
# go) but still fails the run overall.
#
# Versioning, per target:
#   * btrfs targets: the mirror at <target>/opencode is kept as a btrfs
#     subvolume; after each successful rsync a readonly snapshot is taken
#     into <target>/.snapshots/opencode-<stamp> and the snapshot set is
#     pruned to BACKUP_SNAPSHOT_KEEP (default 14, 0 disables pruning). COW
#     snapshots make every pre-rsync DB generation cheap, so a corrupted
#     live DB never silently destroys the last good backup. The first run
#     against a btrfs target bootstraps the subvolume; an existing plain
#     directory is refused with migration instructions. Non-btrfs targets
#     (NTFS/CIFS — the current fu and bitblaster defaults) mirror without
#     versioning and log a one-line warning. Subvolume deletion needs
#     user_subvol_rm_allowed on the filesystem or passwordless sudo; both
#     are attempted before pruning gives up with a warning.
#   * --snapshot: on-demand, consistent per-DB snapshots using sqlite3
#     .backup (WAL-safe, no server stop needed) into
#     <target>/consistent-snapshot-<stamp>/: each DB copied, PRAGMA
#     integrity_check verified ("ok" required), SHA256SUMS + backup.log
#     written. Works on any filesystem; costs a full DB copy per snapshot.
#     `--snapshot [db ...]` limits the run to the named DB files (default:
#     every root-level *.db in the live data dir).
: "${BACKUP_TARGETS:={{ BACKUP_TARGETS|join(' ') }}}"
: "${BACKUP_SNAPSHOT_KEEP:=14}"
: "${BACKUP_SNAPSHOTS:=1}"
: "${BACKUP_SSH:=}"
if [ -n "${BACKUP_ROOT:-}" ]; then
  BACKUP_TARGETS="$BACKUP_ROOT"
fi
DATA_SRC="${HOME}/.local/share/opencode"
CONFIG_SRC="${HOME}/.config/opencode"
SNAPDIR_NAME=".snapshots"
SNAP_PREFIX="opencode"

SCRIPT_NAME="${0##*/}"

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [options] [--snapshot [db ...]]

Mirror opencode user data to every configured backup target
(space-separated; default: {{ BACKUP_TARGETS|join(' ') }}).
Targets may be local paths or user@host:/path remote specs.

Options:
  -n, --dry-run    Show what would transfer without writing anything.
                   Not supported with --snapshot.
      --config     Also mirror ~/.config/opencode/ to
                   <target>/opencode-config/ (skills, prompts,
                   opencode.json, memory-banks).
      --db-only    Mirror only root SQLite DB and auth files. Much faster
                   (seconds) for mid-session refreshes. Destination keeps
                   all other existing content.
      --snapshot   Skip the mirror; write a consistent per-DB snapshot to
                   <target>/consistent-snapshot-<stamp>/ via sqlite3 .backup
                   + integrity_check + sha256. Optional trailing args name
                   DB files (default: all root-level *.db).
  -v, --verbose    Verbose rsync output (per-file list).
  -h, --help       Show this help.

Default (no flags): mirrors ${DATA_SRC}/ to <target>/opencode/ of each
target with --delete and NTFS/CIFS-safe flags (both filesystems have coarse
mtime granularity). --block-size=65536 balances delta-transfer granularity
against protocol overhead. --partial-dir=.rsync-partial makes transfers
resumable across kills. Excludes *.v2ed* migration artifacts.

On btrfs targets each successful mirror is versioned as a readonly
snapshot under <target>/${SNAPDIR_NAME}/. Non-btrfs targets mirror
unversioned.

Environment:
  BACKUP_TARGETS       space-separated target list (overrides default)
  BACKUP_ROOT          single-target override
  BACKUP_SNAPSHOTS     0 disables btrfs snapshotting (default 1)
  BACKUP_SNAPSHOT_KEEP snapshots retained per btrfs target (default 14;
                       0 disables pruning)
  BACKUP_SSH           extra ssh args for remote targets and their btrfs
                       ops (e.g. "-p 2222 -i /key"); also passed to rsync -e
EOF
}

log() { printf '[%(%Y-%m-%dT%H:%M:%S)T] %s\n' -1 "$*"; }

# Run a command on a target host; empty host means run locally. BACKUP_SSH
# word-splits intentionally (it carries option flags).
run_on() {
  local host="$1"
  shift
  if [ -n "$host" ]; then
    # shellcheck disable=SC2086
    ssh ${BACKUP_SSH} "$host" "$@"
  else
    "$@"
  fi
}

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

# Remote specs: user@host:/path (colon before any slash) or rsync:// URLs.
# rsync:// targets mirror fine but support no ssh-driven btrfs ops.
target_host() {
  case "$1" in
    rsync://*|*://*) printf '' ;;
    /*)              printf '' ;;
    *)               printf '%s' "${1%%:*}" ;;
  esac
}

target_path() {
  case "$1" in
    rsync://*) printf '' ;;
    /*)        printf '%s' "$1" ;;
    *)         printf '%s' "${1#*:}" ;;
  esac
}

target_fs_type() {
  local host="$1" path="$2"
  run_on "$host" stat -f -c %T -- "$path" 2>/dev/null || printf 'unknown'
}

# btrfs subvolume delete, tolerating unprivileged filesystems: plain, then
# passwordless sudo, else a warning (prune failures never abort the run).
run_subvol_delete() {
  local host="$1" path="$2"
  if run_on "$host" btrfs subvolume delete "$path" >/dev/null 2>&1; then return 0; fi
  if run_on "$host" sudo -n btrfs subvolume delete "$path" >/dev/null 2>&1; then return 0; fi
  log "warning: could not delete snapshot (mount with user_subvol_rm_allowed or allow sudo): $path"
  return 1
}

# Snapshot-versioned mirrors need <target>/opencode to BE a subvolume.
# Bootstrap it when absent; refuse to convert an existing plain directory.
# Returns nonzero (after logging) so the caller can skip this target without
# aborting the remaining ones.
ensure_mirror_subvolume() {
  local host="$1" target="$2" mirror="$3"
  if run_on "$host" test -e "$mirror"; then
    # A btrfs subvolume root always has inode 256; `btrfs subvolume show`
    # needs root privileges, so stat is the unprivileged-safe check.
    if [ "$(run_on "$host" stat -c %i -- "$mirror" 2>/dev/null || printf 0)" != 256 ]; then
      printf 'error: btrfs target %s: %s exists but is not a subvolume; move it aside (or delete it), then rerun to bootstrap a versioned subvolume\n' \
        "$target" "$mirror" >&2
      return 1
    fi
  else
    log "bootstrapping btrfs subvolume: ${mirror}"
    if ! run_on "$host" btrfs subvolume create "$mirror" 2>/dev/null; then
      if ! run_on "$host" sudo -n btrfs subvolume create "$mirror"; then
        printf 'error: cannot create subvolume %s\n' "$mirror" >&2
        return 1
      fi
    fi
  fi
}

# Echo a name <prefix>-<stamp>[-N] that does not exist under dir yet.
unique_name() {
  local host="$1" dir="$2" prefix="$3" stamp="$4"
  local name="${prefix}-${stamp}" n=1
  while run_on "$host" test -e "${dir}/${name}"; do
    name="${prefix}-${stamp}-${n}"
    n=$((n + 1))
  done
  printf '%s' "$name"
}

snapshot_mirror() {
  local host="$1" path="$2" mirror="$3" keep="$4"
  local stamp name snapdir
  snapdir="${path%/}/${SNAPDIR_NAME}"
  run_on "$host" mkdir -p "$snapdir"
  stamp="$(date +%Y%m%dT%H%M%S)"
  name="$(unique_name "$host" "$snapdir" "$SNAP_PREFIX" "$stamp")"
  if run_on "$host" btrfs subvolume snapshot -r "$mirror" "${snapdir}/${name}" >/dev/null 2>&1; then
    log "snapshot: ${snapdir}/${name}"
  elif run_on "$host" sudo -n btrfs subvolume snapshot -r "$mirror" "${snapdir}/${name}" >/dev/null 2>&1; then
    log "snapshot: ${snapdir}/${name} (via sudo)"
  else
    log "warning: snapshot failed for ${mirror} (versioning skipped this run)"
    return 0
  fi
  if [ "$keep" -gt 0 ]; then
    prune_snapshots "$host" "$snapdir" "$keep" || true
  fi
}

prune_snapshots() {
  local host="$1" snapdir="$2" keep="$3"
  local names total delete_count failures=0
  names="$(run_on "$host" ls -1 -- "$snapdir" 2>/dev/null | grep "^${SNAP_PREFIX}-" | sort || true)"
  [ -n "$names" ] || return 0
  total="$(printf '%s\n' "$names" | grep -c . || true)"
  [ "$total" -gt "$keep" ] || return 0
  delete_count=$((total - keep))
  local to_delete=()
  mapfile -t to_delete < <(printf '%s\n' "$names" | head -n "$delete_count")
  local name
  for name in "${to_delete[@]}"; do
    run_subvol_delete "$host" "${snapdir}/${name}" || failures=$((failures + 1))
  done
  if [ "$failures" -gt 0 ]; then
    log "warning: failed to prune ${failures} snapshot(s) under ${snapdir}"
  fi
}

# --snapshot mode: consistent per-DB copies via sqlite3 .backup.
consistent_snapshot() {
  local target="$1"
  shift
  local dbs=("$@")
  local host path stamp name dest staging db rc=0
  host="$(target_host "$target")"
  path="$(target_path "$target")"
  if [ -z "$path" ]; then
    log "warning: cannot --snapshot to URL-style target, skipping: ${target}"
    return 1
  fi
  if ! run_on "$host" test -d "$path"; then
    log "warning: backup target missing or unmounted, skipping: ${target}"
    return 1
  fi
  stamp="$(date +%Y%m%dT%H%M%S)"
  name="$(unique_name "$host" "$path" "consistent-snapshot" "$stamp")"
  dest="${target%/}/${name}"
  staging="$(mktemp -d "${TMPDIR:-/tmp}/opencode-snapshot.XXXXXX")"
  _SNAP_STAGING="$staging"
  printf '=== consistent SQLite online-backup snapshot ===\nstarted: %s\nsource: %s\n' \
    "$(date +%Y-%m-%dT%H:%M:%S%z)" "$DATA_SRC" >"${staging}/backup.log"
  local ssh_e=()
  if [ -n "$host" ] && [ -n "$BACKUP_SSH" ]; then ssh_e=(-e "ssh ${BACKUP_SSH}"); fi
  for db in "${dbs[@]}"; do
    log "sqlite3 .backup: ${db}"
    sqlite3 "$DATA_SRC/$db" ".backup '${staging}/${db}'" || rc=$?
    if [ "$rc" -ne 0 ]; then
      printf 'error: sqlite3 .backup failed (%d) for %s\n' "$rc" "$db" >&2
      rm -rf "$staging"
      exit "$rc"
    fi
    printf -- '--- sqlite3 .backup ---\nbackup rc=0\n%s\n' \
      "$(ls -la "${staging}/${db}")" >>"${staging}/backup.log"
  done
  local ic
  for db in "${dbs[@]}"; do
    ic="$(sqlite3 "file:${staging}/${db}?mode=ro" 'PRAGMA integrity_check;')"
    if [ "$ic" != "ok" ]; then
      printf 'error: integrity_check failed for snapshot of %s: %s\n' "$db" "$ic" >&2
      rm -rf "$staging"
      exit 1
    fi
    printf -- '--- integrity_check ---\nok\n' >>"${staging}/backup.log"
  done
  ( cd "$staging" && sha256sum -- *.db ) >"${staging}/SHA256SUMS"
  printf 'finished: %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" >>"${staging}/backup.log"
  run_rsync 0 "snapshot delivery: ${staging}/ -> ${dest}/" \
    -a "${ssh_e[@]}" -- "$staging/" "$dest/"
  rm -rf "$staging"
  _SNAP_STAGING=""
  log "consistent snapshot: ${dest}"
}

main() {
  local dry_run=0
  local include_config=0
  local db_only=0
  local snapshot_mode=0
  local verbose=0
  local positional=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -n|--dry-run) dry_run=1; shift ;;
      --config) include_config=1; shift ;;
      --db-only) db_only=1; shift ;;
      --snapshot) snapshot_mode=1; shift ;;
      -v|--verbose) verbose=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  # Re-expose collected positional args; the ${arr[@]+...} idiom keeps an
  # empty array empty under set -u without adding a phantom "" element.
  set -- ${positional[@]+"${positional[@]}"}

  if [ "$snapshot_mode" = 1 ]; then
    if [ "$dry_run" = 1 ] || [ "$include_config" = 1 ] || [ "$db_only" = 1 ]; then
      printf 'error: --snapshot does not combine with --dry-run/--config/--db-only\n' >&2
      exit 2
    fi
  elif [ "$#" -gt 0 ]; then
    printf 'error: unexpected argument: %s (positional args are only valid after --snapshot)\n' "$1" >&2
    exit 2
  fi

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

  local targets=()
  read -ra targets <<<"${BACKUP_TARGETS}"
  if [ -z "${targets[*]:-}" ]; then
    printf 'error: no backup targets configured (BACKUP_TARGETS is empty)\n' >&2
    exit 1
  fi

  # --snapshot mode: per-target consistent DB snapshots, then done.
  if [ "$snapshot_mode" = 1 ]; then
    command -v sqlite3 >/dev/null 2>&1 || {
      printf 'error: --snapshot requires sqlite3\n' >&2
      exit 1
    }
    # Never leak a staged snapshot on any exit path.
    trap 'rm -rf "${_SNAP_STAGING:-}"' EXIT
    local dbs=()
    if [ "$#" -gt 0 ]; then
      local db
      for db in "$@"; do
        if [ ! -f "${DATA_SRC}/${db}" ]; then
          printf 'error: no such DB in %s: %s\n' "$DATA_SRC" "$db" >&2
          exit 1
        fi
        dbs+=("$db")
      done
    else
      local f
      for f in "$DATA_SRC"/*.db; do
        dbs+=("${f##*/}")
      done
      if [ -z "${dbs[*]:-}" ]; then
        printf 'error: no *.db files found in %s\n' "$DATA_SRC" >&2
        exit 1
      fi
    fi
    local failures=0
    local target
    for target in "${targets[@]}"; do
      consistent_snapshot "$target" "${dbs[@]}" || failures=$((failures + 1))
    done
    if [ "$failures" -gt 0 ]; then
      printf 'error: %d target(s) could not take consistent snapshots\n' "$failures" >&2
      exit 1
    fi
    log "done"
    return 0
  fi

  if [ "$include_config" = 1 ] && [ ! -d "$CONFIG_SRC" ]; then
    printf 'error: --config requested but %s missing\n' "$CONFIG_SRC" >&2
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
    log "warning: opencode is running; the live DB may be captured mid-write. For a guaranteed-clean snapshot, quit opencode first (or use --snapshot)."
  fi

  local sources=("$DATA_SRC")
  if [ -d "$CONFIG_SRC" ]; then sources+=("$CONFIG_SRC"); fi

  local failures=0
  local total=0
  local target host path fs_type mirror_path mirror_dest
  for target in "${targets[@]}"; do
    total=$((total + 1))
    host="$(target_host "$target")"
    path="$(target_path "$target")"
    if [ -z "$path" ]; then
      log "warning: URL-style target cannot be snapshot-versioned: ${target}"
    fi
    if ! run_on "$host" test -d "$path"; then
      log "warning: backup target missing or unmounted, skipping: ${target}"
      failures=$((failures + 1))
      continue
    fi
    if [ -z "$host" ]; then
      guard_destination "${target%/}/opencode" "${sources[@]}"
      if [ "$include_config" = 1 ]; then
        guard_destination "${target%/}/opencode-config" "${sources[@]}"
      fi
    fi
    mirror_dest="${target%/}/opencode"
    mirror_path="${path%/}/opencode"
    fs_type="$(target_fs_type "$host" "$path")"
    local versioned=0
    if [ "$fs_type" = "btrfs" ] && [ "$BACKUP_SNAPSHOTS" = 1 ] && [ "$dry_run" = 0 ] && [ -n "$path" ]; then
      if ! ensure_mirror_subvolume "$host" "$target" "$mirror_path"; then
        failures=$((failures + 1))
        continue
      fi
      versioned=1
    elif [ "$fs_type" != "btrfs" ] && [ "$BACKUP_SNAPSHOTS" = 1 ] && [ "$dry_run" = 0 ]; then
      log "note: ${target} is ${fs_type}, not btrfs; mirroring without snapshot versioning"
    fi
    local ssh_e=()
    if [ -n "$host" ] && [ -n "$BACKUP_SSH" ]; then ssh_e=(-e "ssh ${BACKUP_SSH}"); fi
    run_rsync "$dry_run" "data mirror: ${DATA_SRC}/ -> ${mirror_dest}/" \
      "${data_args[@]}" "${ssh_e[@]}" -- "${DATA_SRC}/" "${mirror_dest}/"
    if [ "$include_config" = 1 ]; then
      run_rsync "$dry_run" "config mirror: ${CONFIG_SRC}/ -> ${target%/}/opencode-config/" \
        "${config_args[@]}" "${ssh_e[@]}" -- "${CONFIG_SRC}/" "${target%/}/opencode-config/"
    fi
    if [ "$versioned" = 1 ]; then
      snapshot_mirror "$host" "$path" "$mirror_path" "$BACKUP_SNAPSHOT_KEEP"
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
