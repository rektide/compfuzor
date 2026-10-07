# Handoff: btrfs snapshot + send backup for opencode data

Written 2026-10-07 after a data-loss incident. This is a self-contained prompt for a
fresh session to implement the backup capability. You (the session reading this) have
no other context — everything you need is below.

## Why this exists (incident context)

On 2026-10-07 an operator-approved-then-overrun DB purge deleted 327 sessions from
`~/.local/share/opencode/opencode-local.db` (23.5 GB SQLite, the only copy). Recovery
by carving freed pages recovered essentially nothing (in-page compaction + checkpoint +
8 min of a busy server reusing freed pages). No filesystem snapshots, no backups
existed. The operator then directed: build btrfs snapshots with sends to another
location, as two chained systemd capabilities.

Recovery artifacts from the incident (metadata backup, scanners, logs) live in
`~/tmp-opencode/recovery-20261007/` if you need the forensic record.

## Environment facts (verified 2026-10-07)

- Filesystem: btrfs on `/dev/nvme0n1p6`, mounted `/`, **3.4T total, 96% used, ~148G
  free**. Space is tight: retention must be enforced, and the send target should be
  OFF this filesystem.
- Subvolumes that exist: `steam`, `root-ro`, `root` (id 260, = `/`), a few
  `var/lib/*`. **There is NO `/home` or `/home/rektide` subvolume** — home lives
  inside the `root` subvol. Snapshots are subvolume-granular, so the data dir must
  become its own subvolume first (see migration step).
- Data to protect: `/home/rektide/.local/share/opencode/` — ~33G total, dominated by
  `opencode-local.db` (23.5G) + WAL. It is HOT: written constantly by
  `opencode.service`.
- `opencode.service` is a **user** unit (`systemctl --user`) running
  `opencode serve --hostname 0.0.0.0 --port 49373 --publish`. A clean `stop` can HANG
  when the server is wedged; the known-good recovery is SIGKILL on MainPID. Plan the
  migration window accordingly (stop, verify dead via `/proc`, proceed).
- Passwordless sudo IS available (`sudo -n btrfs subvolume list /` worked).
- btrfs snapshots are crash-consistent, not SQLite-consistent. Optional (recommended)
  consistency pre-step: a tiny unit that runs `sqlite3 ... 'PRAGMA wal_checkpoint(TRUNCATE);'`
  (or `.backup`) against the db before snapshotting.

## What to build

Two capabilities, each its own systemd units, chained so a sequence graph fires:

1. **snapshot** — `btrfs-snap@.service` + `btrfs-snap@.timer` (template unit,
   instance = dataset name, e.g. `btrfs-snap@opencode`). Creates a readonly snapshot
   `-r` of the source subvol into a snapshot pool dir (e.g.
   `/var/lib/btrfs-snap/opencode/<timestamp>` or a top-level `.snapshots-opencode`
   subvol — your call, keep it off the backed-up subvol itself).
2. **send** — `btrfs-send@.service` + `btrfs-send@.timer` (template unit, same
   instance). Incremental `btrfs send -p <parent>` of the newest not-yet-sent
   snapshot to a target elsewhere; track state with a stamp/ledger file (last sent
   snapshot id). On success, allow pruning.

Chaining: prefer `OnSuccess=` from snapshot → send (and an optional
pre-checkpoint → snapshot), while keeping both timers independent so send can also
run on its own cadence and no-op cleanly when nothing new exists. The operator
explicitly wants "each its own unit … a sequence graph that fires" — model it as
small units + systemd dependency edges, not one big script. A prune/retention unit
completes the graph (runs after successful send; deletes local snapshots older than
the retention window, and targetside when applicable).

## Decisions to confirm with the operator before implementing

- **Send target** — where do receives land? (external drive? another machine over
  ssh? a file on another fs?) This is the main unknown.
- Cadence (proposed: hourly snapshots) and retention (proposed: 7 days local).
- Include the SQLite checkpoint pre-step or keep it pure btrfs.

## Guardrails

- The migration to a subvolume is the risky step: stop `opencode.service` (user),
  verify the process is gone, create subvol, `mv`/rsync data in, swap the directory
  back, restart, and confirm the server opens the DB and sessions list normally
  BEFORE doing anything else. Do not VACUUM the 23G db casually.
- Never point a watcher, index, or recursive scan at `$HOME` broadly (see incident
  history: `$HOME`-cwd opencode sessions wedge the server). Concretely: when testing
  restored data, work on copies under `/home/rektide/tmp-opencode`.
- Do a restore drill: `btrfs receive` one snapshot into scratch space and open the db
  read-only (`sqlite3 'file:...?mode=ro'`) to prove the chain works end to end.
- Failure paths: send target unreachable → log, skip, DO NOT accumulate unbounded
  local snapshots past retention cap.

## Future direction (do not build now)

The operator eventually wants a compfuzor `gen_btrfs` subsystem (a `.pb` playbook
generating these units per dataset). For now: build the one instance for the
opencode data dir only, but use the template-unit naming above (`btrfs-snap@`,
`btrfs-send@`) and keep per-instance config (source subvol, target, retention)
factored so the playbook can generate it later.

## Verification checklist

- [ ] subvol migration done, opencode healthy on new subvol
- [ ] snapshot timer fires; readonly snapshot appears
- [ ] sequence graph fires send after snapshot success
- [ ] incremental send works (second snapshot uses `-p`)
- [ ] target-side receive verified by restore drill
- [ ] retention prunes both sides
- [ ] units survive reboot; `systemctl list-timers` shows both
