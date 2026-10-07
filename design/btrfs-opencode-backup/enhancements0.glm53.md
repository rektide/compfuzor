# Enhancement suggestions for design0

Review of [`design0.gpt61sm.md`](/design/btrfs-opencode-backup/design0.gpt61sm.md)
by the g agent (GLM-5.3 max), 2026-10-07, produced independently before
Sol-medium implementation. Scope held to the operator's slice: stream archive
files, 12h snapshots, atomic DB+WAL capture, no checkpoint, no SSH receiver,
destination/retention unresolved, machinery built and tested inactive. Nothing
below was executed against live state: all verification was read-only (man
pages, `systemd-analyze`, `findmnt`, `btrfs subvolume list /`, shipped unit
files, repo sources). Scratch evidence lives in
[`.test-agent/btrfs-backup-units/`](/.test-agent/btrfs-backup-units/README.md).

The design is strong: fail-closed publication, chain-granular archive
retention, and "local state is a cache, manifests are truth" are the right
invariants. The items below are corrections of latent traps, simplifications
that cut the failure matrix, and evidence-backed upgrades. Verdict: after the
must-fix pins, proceed to the `engine` ticket as sliced.

## Verified environment facts (all checked on this host today)

| Fact | Value | How verified |
|---|---|---|
| systemd | 262 (262-1) | `systemctl --version`; `OnSuccess=` exists (man: added in 249) |
| Specifier expansion in dependency values | works | shipped units `e2scrub@.service` (`OnFailure=e2scrub_fail@%i.service`), `pg_dump@.service` (`Wants=postgresql@%i.service`), `systemd-pcrfs@.service` (`BindsTo=%i.mount`); also `systemd-analyze verify` clean on scratch templates. Caveat: verify never flags unresolvable deps, so the shipped-unit precedent is the real evidence |
| **Calendar list parsing** | `OnCalendar=00:00,12:00` fires **00:00 and 00:12**, not midnight+noon; `00:30,12:30` normalizes to `*-*-* 00:12,30:30` | `systemd-analyze calendar --iterations=5` (see must-fix 1) |
| `AccuracySec=` default | 1min | systemd.timer(5) — design need not change anything here |
| `Persistent=` | fires once immediately if it would have elapsed while inactive; OnCalendar-only | systemd.timer(5) |
| btrfs-progs | v7.1 | `btrfs --version` |
| send readonly requirement | "All snapshots involved in one send command must be read-only", including for the duration of the send | btrfs-send(8) verbatim |
| `btrfs send -f <outfile>` | writes the stream to a file directly (no pipe needed) | btrfs-send(8) synopsis |
| receive failure modes | (1) receiving subvolume already exists; (2) previously received subvolume changed after receive; (3) default subvolume/mount issues. Received subvol is made read-only on success | btrfs-receive(8) |
| `btrfs receive --dump` | validates the stream and prints metadata, "The filesystem remains unchanged" | btrfs-receive(8) |
| `flock` | `-w <sec>` bounded wait; `-E/--conflict-exit-code <n>` distinct contention exit (default 1); child exit status passed through otherwise | flock(1), util-linux 2.42.4 |
| journald | persistent (`/var/log/journal` exists) | `ls -d /var/log/journal` |
| source fs | `/dev/nvme0n1p6[/root]`, UUID `d691b804-8828-4c93-916b-9a677c670e82`, 3.4T/96%/148G free | `findmnt`, `df` |
| subvolumes | ids 256–271; no `/home` subvol; `/var/lib` is a plain dir inside root subvol (only nested `var/lib/{portables,machines,k3s-*}` subvols); unrelated `home/rektide/src/btrfs-bot/.test-agent` subvols exist | `sudo -n btrfs subvolume list /` |
| sqlite3 | 3.53.4 installed (drill tooling available) | `sqlite3 --version` |

The design's "systemd is not on PATH" reconnaissance note can be retired:
`/usr/bin/systemctl` and `/usr/bin/systemd-analyze` are present; `OnSuccess=`
is supported at 262. The design's pool proposal `/var/lib/btrfs-snap/opencode`
is consistent with the actual subvol layout (plain dir in root subvol, outside
any source nesting).

## Must-fix (correctness traps in the design as written)

1. **Pin exact `OnCalendar=` strings — the intuitive list syntax is wrong.**
   The unit graph (design lines 91–96) says timers run at "00:00 / 12:00" and
   "00:30 / 12:30". Writing those as `OnCalendar=00:00,12:00` / `00:30,12:30`
   does NOT do that on this host: the comma is a *value list* inside one time
   field, so `00:00,12:00` means hour 00, minutes {00,12} — snapshots at
   midnight and 00:12, never at noon. Verified:
   `systemd-analyze calendar --iterations=5 '00:00,12:00'`. The correct forms
   are `OnCalendar=00/12:00` (fires 00:00, 12:00) and `OnCalendar=00/12:30`
   (fires 00:30, 12:30). The design must carry the literal strings plus a
   test that normalizes cadences via `systemd-analyze calendar` (a
   non-mutating host assertion) or a pinned calendar parser.
2. **Pin the lock file location; never use `RuntimeDirectory=` for it.**
   The shared per-dataset flock (design line 99) is the only real mutual
   exclusion across snapshot/send/prune. If the lock file lives in a directory
   systemd auto-removes when a unit stops (`RuntimeDirectory=`), a stop can
   unlink the path while another unit still holds the flock; the next opener
   creates a *fresh inode* and two units then run "under the same lock"
   concurrently. The lock must live in the persistent `stateDir`
   (`/var/lib/btrfs-backup/opencode/lock`, created by the installer) — not
   `/run`, not any unit-managed directory.
3. **Decide contention-vs-failure semantics explicitly.** flock(1) supports
   `-w <seconds>` with `-E <code>` for a distinct contention exit status.
   Recommendation: `flock -w 600 -E 75`, keep it a genuine unit failure (do
   NOT add `SuccessExitStatus=75`, which would make a contended send count as
   success and cascade `OnSuccess=` into prune). A failed contended run is
   correct behavior: the other unit is doing the work; the next timer edge
   retries. Document 75 in the runbook so `systemctl --failed` noise is
   understandable.
4. **Forbid `immutable=1` when validating restored databases.** The restore
   protocol (design lines 189–197) correctly makes a writable snapshot before
   SQLite inspection — keep that, and make the prohibition explicit: opening
   with `mode=ro&immutable=1` *skips WAL replay* and silently reports the
   stale main-database state while missing every transaction still living in
   the WAL. That can pass `PRAGMA quick_check` and session-count checks while
   validating the wrong recovery point. Validation must open a writable copy
   (normal recovery path), and the drill's expected counts must come from a
   post-snapshot source, since the atomic DB+WAL capture is crash-consistent
   by design (no checkpoint — operator's choice, upheld).
5. **Write streams with `btrfs send -f <staging>/stream.btrfs`, not a Node
   pipe.** btrfs-send(8) writes the outfile itself; ENOSPC mid-stream becomes
   a nonzero btrfs exit with no advertised completion, and the whole class of
   Node-side pipe failures (EPIPE, backpressure bugs, partial file framing)
   disappears. Hash afterward by streaming the closed file through
   `crypto.createHash('sha256')` (no new dependency, constant memory). The
   design's "hash and count streamed bytes" (line 151) survives unchanged;
   only the transport is pinned.
6. **Never mutate received subvolumes during chain replay.** btrfs-receive(8)
   fails if a previously received subvolume "has been changed after it was
   received" — and flipping its readonly property for inspection counts as
   touching it in tooling terms. The rule for the restore code path: receive
   the full chain in order untouched, then take a *writable snapshot* of the
   chosen endpoint for SQLite work (the design already says this at line
   189–191 — elevate it to an invariant alongside line 188, and cover
   "receive into non-empty dir" and "parent changed" failure modes in tests
   with the man page's exact three failure cases).

## Simplifications (cut the failure matrix, keep the invariants)

1. **One rollover trigger: `maxChainLength` only.** Drop `fullEveryHours`
   (design line 77) from v1 config. Age-based rollover adds a second clock to
   reconcile against chain retention (lines 174–179) and protects nothing that
   a stream-count cap doesn't already bound; 12h cadence means a length cap of
   ~14 is a week of incrementals anyway. Add a manual `btrfs-backup send
   --full` escape hatch for operator-driven rebase.
2. **Drop the `send → prune` OnSuccess edge.** Prune is idempotent and
   timer-driven; running it at most half a day after eligibility is
   immaterial against 48h local retention, and removing the edge removes a
   lock-contention window and one graph coupling. The operator's "sequence
   graph" ask stays satisfied by `snapshot → send`. (If Sol keeps the edge,
   contention must-fix 3 becomes load-bearing.)
3. **Make the send timer non-persistent.** With `Persistent=true` on both
   timers, a boot after downtime fires snapshot catch-up and send catch-up
   simultaneously — instant lock contention at boot. Snapshot timer
   `Persistent=true` alone preserves the recovery-point cadence; the send
   timer's catch-up adds nothing (OnSuccess chains send right after the
   catch-up snapshot; the next 12:30 edge would too).
4. **One CLI, three six-line template units.** A single installed
   `btrfs-backup <verb> --dataset %i` keeps units trivial, makes the flock
   wrapper identical everywhere, and matches the repo's TS precedent
   ([`btrfs-balance.ts`](/files/disk-cleanup/btrfs-balance.ts): dry-run
   default, shebang, self-documenting header).
5. **Keep stateDir to lock + cache + status only.** The design already treats
   local last-send state as a cache (lines 154–157); resist any second ledger.
   Archive manifests are the sole truth for what exists remotely.

## Upgrades (cheap, evidence-backed)

1. **`btrfs-backup status` doctor subcommand.** Read local inventory +
   manifests + `statfs`; report last recovery point age, unsent snapshot
   count, chain completeness, headroom; exit nonzero when degraded. This is
   the artifact that actually earns operator trust between drills.
2. **`OnFailure=` stamp.** A tiny failure template writing
   `stateDir/failed-stamp` (checked by `status`) plus journald persistence
   (verified present) gives outage visibility without new infrastructure.
   Shipped `e2scrub_fail@%i` is the precedent pattern.
3. **`btrfs receive --dump` as drill-time stream validation.** Man-verified:
   parse/validate only, "the filesystem remains unchanged" — a cheap
   structural check of archived streams independent of our own hashes.
   Optional at publish time for incrementals (they're small); run it for full
   streams only in drills (a 23G stream parse is minutes).
4. **Resource politeness on send.** `Nice=10`, `IOSchedulingClass=idle`,
   `CPUWeight=50` on the send unit: a full 23.5G stream reads the whole live
   subvol through the page cache while `opencode.service` serves traffic on
   the same disk.
5. **Snapshot admission headroom sizing guidance.** Snapshots pin extents:
   free-space consumption is (churn since oldest retained snapshot), not
   snapshot count. On a 96%-full fs with a multi-GB/day rewriting 23.5G db,
   document that `localMinAvailableBytes` should start ≥ ~30G and that the
   admission check must `statfs` the source fs at snapshot time under the
   lock (design line 120 already rechecks — add the sizing rationale so the
   eventual operator decision is informed).
6. **Host assertions in tests.** `systemd-analyze calendar` and
   `systemd-analyze verify` are installed and non-mutating; wire both into
   the units ticket's checks (verify against copied unit files in a temp dir;
 note it does not catch unresolvable dependencies, so also assert the
   literal `OnCalendar` strings against `calendar` normalization).

## Deferred (agree with design; recording the boundary)

- Compression/encryption of streams. When revisited: btrfs-progs 7.1 supports
  `send --proto 2 --compressed-data` (kernel ≥6.0 both sides), which matters
  for a SQLite-dominated tree; manifest v1 already carries byte count + hash
  so it stays additive.
- SSH/live receiver, `gen_btrfs` playbook, checkpoint pre-step (operator
  excluded), qgroups, balance-driven reclamation — the balance tool's own
  host finding ("no sparse chunks; balance is a null lever today") closes
  that door for now ([`btrfs-balance.ts`](/files/disk-cleanup/btrfs-balance.ts)).

## Tensions and consequential decisions for Sol

- **Contention semantics vs quiet journals** (must-fix 3): genuine failures
  pollute `systemctl --failed`; `SuccessExitStatus` silences them but cascades
  `OnSuccess=`. Recommendation stands with plain failure; revisit only if the
  operator reacts to failed-unit noise.
- **Timer graph shape**: must-fix 1 + simplifications 2–3 change the design's
  mermaid graph (persistent snapshot timer → snapshot → OnSuccess → send;
  independent non-persistent send + prune timers). The operator asked for a
  sequence graph; this still is one, with fewer boot-time races.
- **`fullEveryHours` removal** shrinks the retention/rebase test matrix for
  tickets 3–4; if the operator wants time-bounded chains later it is additive
  config, not a migration.
- **Destination interacts with staging**: staging lives on the archive fs
  (design line 150), so the destination must absorb ~one full stream
  (~23.5G+) of transient space on top of retained chains — worth stating in
  the destination decision ticket; the 148G-free root fs is not a candidate
  (same filesystem, invariant 2).

## Suggested next implementation slice

The `engine` ticket as sliced (config schema, path/identity guards, shared
lock, inventory, readonly snapshot CLI — inactive), with these pins folded
in: exact `OnCalendar=00/12:00` strings, `stateDir` lock with
`flock -w 600 -E 75`, config schema minus `fullEveryHours`, `btrfs send -f`
staging interface, and the `status` skeleton. That keeps archive/retention
tickets consuming an already-correct CLI. Unit tests can run today against
`systemd-analyze` and fake processes under `.test-agent/btrfs-backup/`.

## Cross-references

- [Handoff](/design/btrfs-opencode-backup/handoff.glm53.md): incident facts,
  environment, and the two-capability framing this design implements.
- [design0](/design/btrfs-opencode-backup/design0.gpt61sm.md): the document
  under review; line references above point into it.
- [Historical btrfs scripts](/files/btrfs/subvolumize.sh): 2020-era
  subvolume migration shell — useful precedent for the migration runbook's
  `.bak`-style rollback naming, not for the archive protocol.
- [Disk balance tool](/files/disk-cleanup/btrfs-balance.ts): why headroom
  cannot be reclaimed by balancing on this host today.
- Scratch verification artifacts:
  [`.test-agent/btrfs-backup-units/README.md`](/.test-agent/btrfs-backup-units/README.md).
