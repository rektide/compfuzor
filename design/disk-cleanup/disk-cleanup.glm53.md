---
type: Design
title: disk-cleanup subsystem — post-incident ~/src, journald, and btrfs reclaim
description: Capture of the 2026-10-01 root-fs-full incident response as a compfuzor subsystem: a dry-run-first src-clean.ts, a staged btrfs-balance.ts, and a journald size+time cap drop-in, with the pnpm store and btrfs chunk semantics that shape them.
status: draft
generated: { by: agent:glm53, at: 2026-10-01 }
verified: { by: none, at: null }
sources:
  - id: incident
    resource: https://example.invalid/none
    title: operator report — root btrfs 100% full, k3s crash-loop (etcd fsync starvation, 56 restarts), 2026-10-01 morning
  - id: host-state
    resource: findmnt -n -o FSTYPE,SOURCE /
    title: "btrfs on /dev/nvme0n1p6 (subvol /root) mounted at /; 3.4T device, 99% used, 61G free at design time"
  - id: journald-state
    resource: "du -sh /var/log/journal"
    title: "4.1G of persistent journal — exactly the systemd default cap min(10% of fs, 4G)"
  - id: journald-man
    resource: "man journald.conf"
    title: journald.conf(5) — System* / Runtime* size and retention settings
  - id: pnpm-docs
    resource: https://pnpm.io/cli/store
    title: pnpm store — content-addressable store, hardlink/reflink linking, `pnpm store prune`
  - id: btrfs-wiki
    resource: https://btrfs.readthedocs.io/en/latest/btrfs-balance.html
    title: btrfs-balance(8) — -dusage=N relocates data chunks at or below N% usage
---

# disk-cleanup — why, what, and what still needs a human

## The situation

The morning of 2026-10-01 the root btrfs (`/dev/nvme0n1p6[/root]` on `/`,
~3.4T) hit **100% full** and k3s crash-looped — etcd starved on fsync, 56
restarts before anyone intervened. Free space on this box is precious and
shock-prone: it evaporates in big steps (cargo incremental trees, node
installs, journal growth, btrfs chunk allocation) rather than leaking
smoothly.

The operator has done ad-hoc `~/src` cleanups many times; none were ever
captured. Compfuzor history search found nothing prior — this is
greenfield. This wave captures the cleanup as a reviewable subsystem
instead of muscle memory:

- [`disk-cleanup.opt.pb`](/disk-cleanup.opt.pb) — renders
  `/opt/disk-cleanup-main` (bins + journald drop-in + link plan)
- [`files/disk-cleanup/src-clean.ts`](/files/disk-cleanup/src-clean.ts) —
  `~/src` reclaim reporter, dry-run by default
- [`files/disk-cleanup/btrfs-balance.ts`](/files/disk-cleanup/btrfs-balance.ts) —
  staged data-chunk balance planner, dry-run by default

Design rule threading all three: **destruction is never the default and
never the render's job.** Everything previews; `--apply` (or an operator
`install.sh`) is the only path that changes the machine.

## src-clean.ts — usage and flags

```
src-clean.ts [--root <dir>] [--max-depth N] [--rust-aggressive]
src-clean.ts --apply [--rust-aggressive] [--pnpm-store-prune]
```

| flag | default | meaning |
|---|---|---|
| `--apply` | off | the ONLY deletion path; nothing else removes anything |
| `--root` | `$HOME/src` | scan root |
| `--max-depth` | 6 | directory depth cap; `.git`/`.jj` skipped, `node_modules`/`target` pruned, EACCES quiet |
| `--rust-aggressive` | off | additionally remove `target/<profile>/{deps,build,.fingerprint}` — **forces full rebuilds** |
| `--pnpm-store-prune` | — | apply-mode only (errors without `--apply`); runs `pnpm store prune` after node_modules removal |

What it removes, and deliberately does not:

- **Rust innards, not whole `target/`**: `target/<profile>/incremental/`
  (debug, release, custom profiles), `target/package/`, `target/doc/`.
  A `target/` only counts when a `Cargo.toml` sits beside it. The build
  skeleton and most compiled artifacts survive, so the next build is
  incremental-but-slower, not from-scratch.
- **Whole `node_modules/` trees**, traversal pruned at the first one (a
  nested one is unreachable once the outer tree goes). A `--root` that
  is itself a `node_modules` is treated as a single candidate, never
  mined for nested ones.

Sizes are block usage (`st_blocks × 512`, `du -s` parity, hardlinks
counted once per traversal) and reported as **upper bounds**.

### Sample dry-run (bounded, read-only; 2026-10-01)

```
$ node files/disk-cleanup/src-clean.ts --root ~/src/facet-caminus --max-depth 4
src-clean.ts: DRY RUN (no --apply) — nothing will be deleted
root: /home/rektide/src/facet-caminus  max-depth: 4  rust-aggressive: off

candidates:
       SIZE  CATEGORY           PATH
   1.3 GiB  rust-safe          /home/rektide/src/facet-caminus/target/debug/incremental
 328.0 KiB  rust-safe          /home/rektide/src/facet-caminus/target/package
       0 B  rust-safe          /home/rektide/src/facet-caminus/target/doc

totals — space freed by unlinking (UPPER bound; see pnpm semantics in --help):
  rust-safe            1.3 GiB  (3 dirs)
  total                1.3 GiB

pnpm store:
  store path: /home/rektide/.local/share/pnpm/store/v11 (size 8.5 GiB, via bounded du -s)
  space freed by `pnpm store prune`: up to 8.5 GiB (upper bound —
    prune releases only packages no longer referenced by any project)
  note: unlinking store-linked node_modules frees ~0 by itself; the store
        prune is what releases bytes, and it only counts after projects
        stopped referencing the content (i.e. after node_modules removal).

skipped: 0 unreadable dir(s) (quiet), 1 pruned subtree(s) (node_modules/target)

commands that would run (with --apply):
  rm -rf -- /home/rektide/src/facet-caminus/target/debug/incremental
  rm -rf -- /home/rektide/src/facet-caminus/target/package
  rm -rf -- /home/rektide/src/facet-caminus/target/doc
```

With `--rust-aggressive` the same repo reports ~6.6 GiB (adds
`debug/deps` 5.6 GiB, `release/deps`, `debug/build`, `.fingerprint` …),
and when a profile dir would empty completely the plan appends
`rmdir --ignore-fail-on-non-empty -- <profile>`.

## pnpm store semantics — freeing space vs cheap re-install

pnpm does not copy packages into each project's `node_modules`. It keeps
one **content-addressable store** (`pnpm store path` — here
`~/.local/share/pnpm/store/v11`, 8.5 GiB) and links each project's files
into it by **hardlink** (same filesystem) or **reflink** (btrfs/CoW).
Two consequences drive the whole design:

1. **Deleting a project's `node_modules` frees almost nothing** while the
   store still holds the content: the blocks belong to the store; the
   project only held links to inodes. `du` cannot see this (it counts
   per-traversal), so the report marks pnpm-managed trees
   `[pnpm: store-linked]` and keeps "space freed by unlinking" and
   "space freed by store prune" in separate totals. Real bytes come back
   only from `pnpm store prune`, which removes store content **no
   project references any more** — so it pays off *after* node_modules
   removal, never instead of it. Hence: `--pnpm-store-prune` runs last,
   apply-mode only.
2. **Re-install after only deleting `node_modules` is cheap**: it is a
   re-link from the store, no re-download, no rebuild of native
   artifacts that live in the store. That asymmetry is why removing
   whole `node_modules/` trees (safe, recoverable in minutes) is the
   default while rust `deps/` removal (forces recompiles) is opt-in.

## btrfs-balance.ts — why ascending dusage stages

The root fs is **fully chunk-allocated**: btrfs handed out all chunks,
so free space hides inside partially-used data chunks. Only relocation
(`btrfs balance start -dusage=N`) empties chunks at-or-below N% usage so
the allocator can reuse them. Stages:

| stage | what it relocates | cost |
|---|---|---|
| `-dusage=2` | nearly-empty chunks | cheapest per reclaimed chunk; usually the big win |
| `-dusage=8` | still-sparse chunks | cheap; catches chunks stage 1 redistributed below the line |
| `-dusage=20` | ≤20%-used chunks | moderate IO, meaningful rewrite |
| `-dusage=45` | ≤45%-used chunks | a big rewrite of live data |
| `-dusage=65` (`--deep`, off) | ≤65%-used chunks | rewrites huge amounts of live data for marginal reclaim |

Why ascending rather than one high pass: emptying the nearly-empty
chunks first **consolidates** live data into fewer chunks, pushing more
chunks below the next threshold — each stage reconsiders what the
previous one made sparse. A single `-dusage=45` pass would rewrite
everything at once with no chance to stop early when "enough" is
reclaimed. 45% is already "rewrite up to ~half of each target chunk";
65% is opt-in because past ~50% the cost/benefit is poor on most
filesystems.

Guards: refuses to run — **even dry-run** — unless `findmnt` reports the
target as btrfs (verified: tmpfs `/dev/shm` → clean refusal, exit 1);
`--apply` checks euid and prints the sudo invocation instead of
half-failing; stages abort the chain on first failure, keeping progress
already balanced. Heavy IO is warned in `--help`: run idle, never during
builds, never with etcd/databases live.

Sample dry-run excerpt:

```
$ node files/disk-cleanup/btrfs-balance.ts
btrfs-balance.ts: DRY RUN (no --apply) — printing commands only, nothing will run
target: / (fstype btrfs, confirmed via findmnt)

before:  btrfs filesystem usage /   # note Data size / unallocated

  btrfs balance start -dusage=2 /
    relocates data chunks ≤2% used (nearly-empty). Cheap and fast; on a
  fully-allocated fs this commonly frees the most chunks per GiB rewritten.
  ...
to execute: sudo btrfs-balance.ts --apply
```

## journald — the answer: BOTH time and size caps exist

`journald.conf(5)` limits the journal on two independent axes, and the
stock defaults explain today's 4.1G `/var/log/journal` exactly:

**Size** (persistent `/var/log/journal`):

| setting | default | notes |
|---|---|---|
| `SystemMaxUse` | `min(10% of fs, 4G)` | on this 3.4T root → 4G, hence 4.1G on disk (current files may overshoot slightly before rotation) |
| `SystemKeepFree` | `min(15% of fs, 4G)` | journal shrinks to keep this much free |
| `SystemMaxFileSize` | `SystemMaxUse / 8` | per-file cap; smaller → more aggressive rotation |

**Time**:

| setting | default | notes |
|---|---|---|
| `MaxRetentionSec` | `0` = **forever** | the reason nothing ever aged out |
| `MaxFileSec` | 1month | per-file age; only truncates at rotation time |

The **runtime** journal (`/run/log/journal`) has parallel
`RuntimeMaxUse`/`RuntimeKeepFree`/`RuntimeMaxFileSize` settings; not
touched here since the persistent journal is the disk consumer.

Chosen policy (playbook vars, retunable at run time with `-e`):

```ini
[Journal]
SystemMaxUse=1G          # was min(10%, 4G) → 4.1G actual
SystemKeepFree=4G        # shrink harder when the fs is tight
MaxRetentionSec=1month   # was 0 (forever)
```

Installed as a drop-in under `/etc/systemd/journald.conf.d/` (linked
operator-time via the LINKS plan — auto-sudo; `LINKS_BYPASS=True` skips).
The running daemon does not re-read config on its own, and a cap never
shrinks existing files retroactively, so after linking the one-shot
runbook (**operator decision; deliberately not automated**):

```
journalctl --vacuum-size=1G     # immediate reclaim of ~3.1G
sudo systemctl restart systemd-journald   # or SIGUSR2 to just flush
```

## What is deliberately NOT done here

- No `--apply` runs, no playbook execution against the host, no
  `journalctl --vacuum`, no balance — this wave is capture + dry-run
  verification only (syntax-check + bounded read-only smoke tests).
- No systemd unit/timer runs anything periodically: both scripts are
  operator-invoked. Automating them is a possible follow-up, but each
  needs an interactive risk/reward read (full rebuilds, heavy IO) that
  shouldn't be scheduled blindly.

## Open questions for the operator

1. **journald values** — 1G/4G/1month sit where "post-incident
   conservative" landed. If k3s postmortems need longer boot-to-crash
   journal history, raise `SystemMaxUse` (2G?) and keep the retention.
2. **First real run** — approve `--apply` order: journald vacuum first
   (frees ~3.1G immediately, zero risk), then `src-clean` default pass
   (rust incremental + node_modules), then decide `--pnpm-store-prune`
   (cheap re-install guarantee weakens for anything pruned), and only
   then consider `btrfs-balance` stages in an idle window.
3. **`--rust-aggressive`** — is a full-rebuild-for-space trade ever
   wanted as policy, or only as an explicit one-off? Current answer:
   one-off only (default off, no automation).
4. **k3s snapshot/backup location** — the incident showed etcd state and
   journal on the same shock-prone fs; worth a separate wave?
5. **Runtime journal** — `/run` journal is tmpfs (RAM); leave untouched?
   Current answer: yes.

## References

- Playbook: [`disk-cleanup.opt.pb`](/disk-cleanup.opt.pb) — commit `d2a53dc6978e`
- Scripts: [`files/disk-cleanup/src-clean.ts`](/files/disk-cleanup/src-clean.ts) — commit `d6602f2e5670`;
  [`files/disk-cleanup/btrfs-balance.ts`](/files/disk-cleanup/btrfs-balance.ts) — commit `2198e6c3d823`
- Patterns followed: [`k3s.srv.pb`](/k3s.srv.pb) (`raw: True` bins from `files/`),
  [`kernel-usb-autosuspend.etc.pb`](/kernel-usb-autosuspend.etc.pb) (ETC_FILES + LINKS drop-in),
  [`crashkernel.etc.pb`](/crashkernel.etc.pb) (README-as-documentation, BINS_RUN_BYPASS rationale)
- Verification: `ansible-playbook disk-cleanup.opt.pb --syntax-check` (pass, no-inventory warnings only);
  dry-run smoke tests above (read-only, bounded `--root`/`--max-depth`)
- Host facts at design time: node v26.6.0 (plain `#!/usr/bin/env node` type-strips);
  `/` = btrfs `/dev/nvme0n1p6[/root]`, 99% used, 61G free; pnpm store v11 = 8.5 GiB
