---
type: Design
title: disk-cleanup subsystem — post-incident ~/src, journald, and btrfs reclaim
description: Capture of the 2026-10-01 root-fs-full incident response as a compfuzor subsystem — one bin per clean (src-clean, rust-aggressive, pnpm-prune + weekly user timer, rustup-clean, btrfs-balance) plus the live journald size+time cap drop-in — with the pnpm store and btrfs chunk semantics that shape them and the measured host results of the first sanctioned runs.
status: stable
generated: { by: agent:glm53, at: 2026-10-01 }
verified: { by: human:rektide, at: 2026-10-01 }
sources:
  - id: incident
    resource: https://example.invalid/none
    title: operator report — root btrfs 100% full, k3s crash-loop (etcd fsync starvation, 56 restarts), 2026-10-01 morning
  - id: host-results
    resource: https://example.invalid/none
    title: operator execution report 2026-10-01 — journald drop-in live (SystemMaxUse=2G, vacuum freed 2G, journal 2.1G), pnpm store prune freed 6.0GB/140,780 files (df ~62G free), manual balance 2/8/20 relocated 0/0/1 of 3340 chunks
  - id: host-state
    resource: findmnt -n -o FSTYPE,SOURCE /
    title: "btrfs on /dev/nvme0n1p6 (subvol /root) mounted at /; 3.4T device, 99% used at design time; ~62G free after the first sanctioned runs"
  - id: journald-state
    resource: "du -sh /var/log/journal"
    title: "4.1G of persistent journal at incident time (systemd default cap min(10% of fs, 4G)); 2.1G after vacuum + 2G cap"
  - id: journald-man
    resource: "man journald.conf"
    title: journald.conf(5) — System* / Runtime* size and retention settings
  - id: pnpm-docs
    resource: https://pnpm.io/cli/store
    title: pnpm store — content-addressable store, hardlink/reflink linking, `pnpm store prune`
  - id: btrfs-wiki
    resource: https://btrfs.readthedocs.io/en/latest/btrfs-balance.html
    title: btrfs-balance(8) — -dusage=N relocates data chunks at or below N% usage
  - id: systemd-user-units
    resource: "skill/systemd.md + tasks/compfuzor/vars_systemd_unit.tasks"
    title: compfuzor user-scope unit mechanism — SYSTEMD_SCOPE/INSTALL user, SYSTEMD_ROOTS, ${HOME} unit-dir runtime roots, install-*-user.sh via systemctl --user
  - id: rustup-state
    resource: "rustup toolchain list + du -sh ~/.rustup"
    title: "25 toolchains / 33G in ~/.rustup at design time — 24.1 GiB across 20 removal candidates under default keeper policy"
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
  `/opt/disk-cleanup-main` (bins + journald drop-in + link plan + the
  pnpm-prune user units)
- [`files/disk-cleanup/src-clean.ts`](/files/disk-cleanup/src-clean.ts) —
  default pass: rust-safe `target/` innards; node_modules opt-in
- [`files/disk-cleanup/rust-aggressive.ts`](/files/disk-cleanup/rust-aggressive.ts) —
  the deps/build/.fingerprint sweep (forces full rebuilds), its own bin
- [`files/disk-cleanup/pnpm-prune.ts`](/files/disk-cleanup/pnpm-prune.ts) —
  `pnpm store prune` wrapper; run weekly by a systemd **user** timer
- [`files/disk-cleanup/rustup-clean.ts`](/files/disk-cleanup/rustup-clean.ts) —
  keeper-policy `~/.rustup` toolchain cleanup
- [`files/disk-cleanup/btrfs-balance.ts`](/files/disk-cleanup/btrfs-balance.ts) —
  staged data-chunk balance planner with a stage cap
- [`files/disk-cleanup/lib.ts`](/files/disk-cleanup/lib.ts) — shared
  helpers (duBytes, spawn, glob matching; not a command)

Operator structure (2026-10-01, binding): **one subsystem, one bin per
clean** — explicitly not a playbook per clean. The compfuzor-generated
`status.sh` remains the subsystem status; scheduled cleans additionally
get systemd **user** units, whose `systemctl --user status` output is
the per-clean "reciprocal status".

Design rule threading all of it: **destruction is never the default and
never the render's job.** Everything previews; `--apply` (or an operator
`install.sh`) is the only path that changes the machine — the single
sanctioned exception being the pnpm-prune timer, whose weekly schedule
IS the operator's standing approval.

## Host results (2026-10-01, post-sign-off)

The operator executed the first runbook; measured results, folded into
the sections below:

| action | result |
|---|---|
| journald drop-in install | **live** at `/etc/systemd/journald.conf.d/disk-cleanup-main.conf`, `SystemMaxUse=2G` (operator picked 2G over the proposed 1G — postmortem headroom) |
| `journalctl --vacuum-size=2G` + restart | freed **2G**; journal now **2.1G** |
| `pnpm store prune` | freed **6.0 GB / 140,780 files**; store 8.5 → 1.2 GiB |
| df free | **~62G** free after the above |
| staged balance 2→8→20 (manual — the tool lacked a stage cap then) | relocated **0 / 0 / 1 of 3340 chunks** |

The balance row is the structural finding: **this fs has no sparse
chunks** — the 3.22 TiB is dense live data, so balance is a null lever
here *today* and the 45/65 stages would rewrite large amounts of live
data for ~1GiB chunks. Not worth it absent new evidence (see the
btrfs section). `--dusage-cap` exists because that manual run had to
happen by hand.

## src-clean.ts — usage and flags

```
src-clean.ts [--root <dir>] [--max-depth N]
src-clean.ts --apply [--node-modules] [--pnpm-store-prune]
```

| flag | default | meaning |
|---|---|---|
| `--apply` | off | the ONLY deletion path; nothing else removes anything |
| `--root` | `$HOME/src` | scan root |
| `--max-depth` | 6 | directory depth cap; `.git`/`.jj` skipped, `node_modules`/`target` pruned, EACCES quiet |
| `--node-modules` | **off** | opt-in anti-feature: also remove whole `node_modules/` trees (see pnpm semantics — rarely frees bytes; for dirent/inode bloat and broken trees) |
| `--pnpm-store-prune` | — | apply-mode only (errors without `--apply`); runs `pnpm store prune` after removals |

What it removes, and deliberately does not:

- **The default pass is rust-safe innards only**: `target/<profile>/incremental/`
  (debug, release, custom profiles), `target/package/`, `target/doc/`.
  A `target/` only counts when a `Cargo.toml` sits beside it. The build
  skeleton and most compiled artifacts survive, so the next build is
  incremental-but-slower, not from-scratch.
- **`node_modules/` removal is an opt-in anti-feature** (operator
  decision 2026-10-01): pnpm trees are store hardlinks/reflinks, so
  unlinking them frees ~nothing — the measured 6.0 GB came from the
  store prune alone. The sweep stays for the rare cases where the
  directory entries themselves are the problem (dirent/inode bloat,
  broken trees). Traversal prunes at the first `node_modules` found; a
  `--root` that is itself a `node_modules` is treated as a single
  candidate, never mined for nested ones.
- **The aggressive sweep is not here any more**: `deps/build/.fingerprint`
  moved to its own bin, rust-aggressive.ts — a different risk class, not
  a bigger version of the same one.

Sizes are block usage (`st_blocks × 512`, `du -s` parity, hardlinks
counted once per traversal) and reported as **upper bounds**.

### Sample dry-run (bounded, read-only; 2026-10-01, BEFORE the on-host default pass ran)

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

The same repo after the operator ran the default pass on-host (the
`1.3 GiB` incremental above is gone; the store section now reports the
post-prune store):

```
$ node files/disk-cleanup/src-clean.ts --root ~/src/facet-caminus --max-depth 4
src-clean.ts: DRY RUN (no --apply) — nothing will be deleted
root: /home/rektide/src/facet-caminus  max-depth: 4  node-modules: off

candidates:
  (none found)
```

With `--node-modules`, pnpm-managed trees are tagged so the report
cannot mislead about what unlinking buys:

```
  244.1 MiB  node-modules       /home/rektide/src/accesskitten/node_modules  [pnpm: store-linked]
```

When a profile dir would empty completely, the plan appends
`rmdir --ignore-fail-on-non-empty -- <profile>`.

## rust-aggressive.ts — the full-rebuild trade

```
rust-aggressive.ts [--root <dir>] [--max-depth N]
rust-aggressive.ts --apply [--root <dir>]
```

Owns exactly the sweep src-clean refuses to default: `target/<profile>/
{deps,build,.fingerprint}`. These hold the compilation output cache;
removing them **FORCES FULL REBUILDS** — every touched workspace
recompiles all dependencies on its next `cargo build` (no re-download:
crate sources live in `~/.cargo`). The warning is in `--help`, in the
report, and again at apply time. Worth it only when reclaim is needed
now, the machine is idle, and the recompile tax is acceptable.

Sample dry-run on the same repo (the build cache is still there — only
the default pass ran on-host):

```
$ node files/disk-cleanup/rust-aggressive.ts --root ~/src/facet-caminus --max-depth 4
rust-aggressive.ts: DRY RUN (no --apply) — nothing will be deleted
candidates (ALL of these force full rebuilds when removed):
       SIZE  PATH
   5.6 GiB  /home/rektide/src/facet-caminus/target/debug/deps
 387.1 MiB  /home/rektide/src/facet-caminus/target/release/deps
 249.6 MiB  /home/rektide/src/facet-caminus/target/debug/build
   15.2 MiB  /home/rektide/src/facet-caminus/target/release/build
   14.4 MiB  /home/rektide/src/facet-caminus/target/debug/.fingerprint

cost: next `cargo build` in each touched workspace recompiles ALL dependencies
```

## pnpm store semantics — freeing space vs cheap re-install

pnpm does not copy packages into each project's `node_modules`. It keeps
one **content-addressable store** (`pnpm store path` — here
`~/.local/share/pnpm/store/v11`, 8.5 GiB at incident time, 1.2 GiB
after the first prune) and links each project's files into it by
**hardlink** (same filesystem) or **reflink** (btrfs/CoW). Two
consequences drive the whole design:

1. **Deleting a project's `node_modules` frees almost nothing** while the
   store still holds the content: the blocks belong to the store; the
   project only held links to inodes. `du` cannot see this (it counts
   per-traversal), so the report marks pnpm-managed trees
   `[pnpm: store-linked]` and keeps "space freed by unlinking" and
   "space freed by store prune" in separate totals. Real bytes come back
   only from `pnpm store prune`, which removes store content **no
   project references any more** — so it pays off *after* node_modules
   removal, never instead of it. **Measured on this host 2026-10-01:
   prune alone freed 6.0 GB / 140,780 files; node_modules unlinking
   ~nothing by itself.** That measurement is what demoted
   `--node-modules` to an opt-in anti-feature and made the STORE, not
   the trees, the thing that gets scheduled.
2. **Re-install after only deleting `node_modules` is cheap**: it is a
   re-link from the store, no re-download, no rebuild of native
   artifacts that live in the store — as long as the store still holds
   the content (anything pruned re-downloads). This asymmetry is why
   the store prune is the standing weekly clean while rust `deps/`
   removal (forces recompiles) stays an explicit one-off bin.

### pnpm-prune.ts + the weekly user timer

`pnpm-prune.ts` is the prune as a bin: dry-run reports the store path,
size (bounded `du -s`), and the exact command; `--apply` runs
`pnpm store prune`.

```
$ node files/disk-cleanup/pnpm-prune.ts
pnpm-prune.ts: DRY RUN (no --apply) — nothing will run
store path: /home/rektide/.local/share/pnpm/store/v11 (size 1.2 GiB, via bounded du -s)
prune releases up to 1.2 GiB (upper bound — only unreferenced content goes)

command that would run (with --apply):
  pnpm store prune
```

The schedule is `disk-cleanup-main-pnpm-prune.{service,timer}` as
systemd **user** units — the operator's standing sanction: **the timer
IS the apply** (ExecStart passes `--apply`; interactive runs stay
dry-run). Mechanism (per `skill/systemd.md` +
`tasks/compfuzor/vars_systemd_unit.tasks`): `SYSTEMD_SCOPE: user` +
`SYSTEMD_INSTALL: user` + `SYSTEMD_ROOTS` renders the unit files as
ETC_FILES, contributes LINKS records with `${HOME}/.config/systemd/user`
runtime roots (links.mjs expands them — **no sudo**), and generates
`install-service-...-user.sh`/`install-timer-...-user.sh` bins driving
`systemctl --user`. `OnCalendar=weekly`, `Persistent=true`.

**enable-linger was explicitly DECLINED by the operator**: nothing
enables it. The timer fires while the user has a session — always-on
user sessions here keep the weekly cadence without it. The per-clean
reciprocal status is the user unit itself:
`systemctl --user status disk-cleanup-main-pnpm-prune.{service,timer}`
(alongside the subsystem `bin/status.sh`).

## btrfs-balance.ts — why ascending dusage stages (and why they were a null lever here)

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

`--dusage-cap N` keeps only stages with dusage ≤ N (clamping `--deep`
too; a cap below the smallest stage is a usage error), because the
manual 2→8→20 run on 2026-10-01 had to stop at 20 by hand:

```
$ node files/disk-cleanup/btrfs-balance.ts --dusage-cap 20
btrfs-balance.ts: DRY RUN (no --apply) — printing commands only, nothing will run
target: / (fstype btrfs, confirmed via findmnt)
stages: 2 → 8 → 20  (capped at --dusage-cap 20)
skipped by cap: 45
...
to execute: sudo btrfs-balance.ts --apply --dusage-cap 20
```

Guards: refuses to run — **even dry-run** — unless `findmnt` reports the
target as btrfs (verified: tmpfs `/dev/shm` → clean refusal, exit 1);
`--apply` checks euid and prints the sudo invocation instead of
half-failing; stages abort the chain on first failure, keeping progress
already balanced. Heavy IO is warned in `--help`: run idle, never during
builds, never with etcd/databases live.

### Host finding: no sparse chunks (2026-10-01)

The operator's manual staged run relocated **0 / 0 / 1 of 3340 data
chunks** across `-dusage=2/8/20`: this filesystem has **no sparse
chunks** — the 3.22 TiB is dense live data. Consequences:

- Balance is a **null lever here today**; the 2/8/20 stages cost a
  chunk-rewrite each and reclaimed effectively nothing.
- The 45/65 stages would rewrite large amounts of live data for ~1GiB
  chunks — **not worth it on this fs absent new evidence**.
- The tool stays because big deletions change the picture: src-clean
  passes and toolchain uninstalls (rustup-clean alone has ~24 GiB of
  candidates) free whole extents and can leave chunks sparse. Re-run the
  CHEAP stages (`--dusage-cap 20`) after such deletions; check
  `btrfs filesystem usage /` for actual Data/unallocated movement before
  believing any stage helped.

## rustup-clean.ts — the biggest untapped reclaim

`~/.rustup` holds ~25 toolchains / 33G here — more than src and pnpm
combined. `rustup-clean.ts` lists them with sizes and applies a keeper
policy; `--apply` uninstalls via `rustup toolchain uninstall` only
(rustup clears its own metadata; `rm` would not).

```
rustup-clean.ts [--keep-stables N] [--keep-nightlies N] [--keep GLOB]...
rustup-clean.ts --apply [...]
```

Keep, in order: the **default** (`rustup default`), the **active**
(`rustup show active-toolchain`, which resolves `RUSTUP_TOOLCHAIN` env
and rust-toolchain file overrides — the list's `(active)` annotation is
honored too), the **N newest stables** (`--keep-stables`, default 2;
tracking `stable` counts as newest, semver pins rank below by version),
the **N newest nightlies** (`--keep-nightlies`, default 2; tracking
`nightly` newest, dated by date), and any **`--keep` glob**. Custom /
linked / unknown-channel toolchains are always kept — deliberate
installs the policy does not understand. Channel parsing peels the host
triple by vendor marker (`x86_64-unknown-linux-gnu` is 4 dash tokens;
a naive last-3 rule misclassified half the list on the first cut).

First scan against live host state (24.1 GiB of candidates):

```
$ node files/disk-cleanup/rustup-clean.ts
rustup-clean.ts: DRY RUN (no --apply) — nothing will be uninstalled
default: stable-x86_64-unknown-linux-gnu   active: nightly-2026-09-30-x86_64-unknown-linux-gnu
policy: keep 2 newest stable(s), 2 newest nightly/nightlies, default, active, --keep globs

toolchains:
       SIZE  DISPOSITION  NAME
   2.5 GiB  keep          nightly-x86_64-unknown-linux-gnu  (nightly #1 of keep-window 2)
   1.6 GiB  keep          stable-x86_64-unknown-linux-gnu  (default toolchain)
   1.6 GiB  keep          nightly-2026-09-30-x86_64-unknown-linux-gnu  (active toolchain)
   1.6 GiB  REMOVE        1.90-x86_64-unknown-linux-gnu  (beyond keep window (stable))
   1.5 GiB  keep          nightly-2026-10-01-x86_64-unknown-linux-gnu  (nightly #2 of keep-window 2)
   1.5 GiB  keep          1.98.0-x86_64-unknown-linux-gnu  (stable #2 of keep-window 2)
   ...

totals: keep 8.6 GiB (5), remove 24.1 GiB (20) — upper bounds

commands that would run (with --apply):
  rustup toolchain uninstall nightly-2025-11-21-x86_64-unknown-linux-gnu
  rustup toolchain uninstall 1.74.0-x86_64-unknown-linux-gnu
  ...
```

Semver pins heads-up: removing a version a `rust-toolchain.toml` pins
does not break builds — rustup shims re-download it on demand — but
that costs network + a few hundred MB on that project's next build.
`--keep` pins when in doubt; the dry run names every candidate.

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
SystemMaxUse=2G          # operator decision 2026-10-01: 2G, not 1G (postmortem headroom)
SystemKeepFree=4G        # shrink harder when the fs is tight
MaxRetentionSec=1month   # was 0 (forever)
```

Installed as a drop-in under `/etc/systemd/journald.conf.d/` (linked
operator-time via the LINKS plan — auto-sudo; `LINKS_BYPASS=True` skips).
**LIVE since 2026-10-01**: the drop-in is installed at
`/etc/systemd/journald.conf.d/disk-cleanup-main.conf`, the one-shot
vacuum ran (freed 2G; journal now 2.1G), and the daemon was restarted.
The runbook remains for future retunes (a cap never shrinks existing
files retroactively):

```
journalctl --vacuum-size=2G     # immediate reclaim of ~2.1G
sudo systemctl restart systemd-journald   # or SIGUSR2 to just flush
```

## What is deliberately NOT done here

- No `--apply` runs by the agent, no playbook execution against the
  host, no `journalctl --vacuum`, no balance — this wave is capture +
  dry-run verification only (syntax-check + bounded read-only smoke
  tests). Everything actually executed on-host so far was run by the
  operator under sign-off.
- No *unsanctioned* periodic execution: the only scheduled clean is the
  pnpm-prune user timer, whose weekly cadence IS the operator's standing
  approval. rust-aggressive and btrfs-balance in particular stay
  operator-invoked one-offs (full-rebuild and heavy-IO trades deserve an
  interactive risk read each time).
- No enable-linger, ever (operator-declined): the timer fires while the
  user has a session.

## Open questions for the operator

1. **journald values** — ANSWERED 2026-10-01: operator chose
   `SystemMaxUse=2G` (postmortem headroom), keep `SystemKeepFree=4G` and
   `MaxRetentionSec=1month`. Drop-in live; vacuum run; journal 2.1G.
2. **First real run** — EXECUTED 2026-10-01 (operator): journald vacuum,
   `pnpm store prune` (6.0 GB), src-clean default pass, manual balance
   2/8/20. Remaining from that ladder: whether to ever run
   `rust-aggressive --apply` (facet-caminus alone holds ~6.3 GiB) —
   one-off only.
3. **`--rust-aggressive`** — ANSWERED by restructure: its own bin,
   operator-invoked one-off; never scheduled.
4. **rustup-clean apply** — the biggest remaining number (24.1 GiB / 20
   toolchains on first scan). Keeper defaults (2 stables + 2 nightlies
   + default + active) sane? Any semver pins worth `--keep` before the
   first `--apply` (rust-toolchain.toml pins re-download on demand)?
5. **Timer enable** — the pnpm-prune user units render with the next
   playbook run; enabling is the operator step
   (`systemctl --user enable --now disk-cleanup-main-pnpm-prune.timer`
   or `bin/install.sh` units lane). Confirm the first fire and the
   `systemctl --user status` reciprocal readout.
6. **k3s snapshot/backup location** — the incident showed etcd state and
   journal on the same shock-prone fs; worth a separate wave?
7. **Runtime journal** — `/run` journal is tmpfs (RAM); leave untouched?
   Current answer: yes.

## References

- Playbook: [`disk-cleanup.opt.pb`](/disk-cleanup.opt.pb) — initial wiring `d2a53dc6978e`,
  restructure (bins + user timer) `1c31259e`
- Scripts under [`files/disk-cleanup/`](/files/disk-cleanup):
  `src-clean.ts` (initial `d6602f2e5670`, restructure `671e574dcf98`),
  `btrfs-balance.ts` (`2198e6c3d823`, stage cap `891baede6cab`),
  `rustup-clean.ts` (`5b1c538f`), `pnpm-prune.ts` (`61cf09b8`),
  `rust-aggressive.ts` + `lib.ts` (`671e574dcf98`)
- Design doc: this file (`a87e321894e8`, host-results fold-in follows);
  operator retune commit `1aca61a7c4c0` (journald 1G→2G)
- Patterns followed: [`k3s.srv.pb`](/k3s.srv.pb) (`raw: True` bins from `files/`,
  SYSTEMD_ROOTS timer+service pair),
  [`kernel-usb-autosuspend.etc.pb`](/kernel-usb-autosuspend.etc.pb) (ETC_FILES + LINKS drop-in),
  [`crashkernel.etc.pb`](/crashkernel.etc.pb) (README-as-documentation, BINS_RUN_BYPASS rationale),
  [`mise.opt.pb`](/mise.opt.pb) + [`opencode.src.pb`](/opencode.src.pb)
  (user-scope units from a system-located subsystem), and
  [skill/systemd.md](/skill/systemd.md) + `tasks/compfuzor/vars_systemd_unit.tasks`
  (the SYSTEMD_SCOPE/INSTALL user mechanism itself)
- Verification: `ansible-playbook disk-cleanup.opt.pb --syntax-check`
  (pass, no-inventory warnings only); dry-run smoke tests above
  (read-only, bounded `--root`/`--max-depth`; rustup-clean dry-run ran
  against the full live `rustup toolchain list`)
- Host facts: node v26.6.0 (plain `#!/usr/bin/env node` type-strips);
  `/` = btrfs `/dev/nvme0n1p6[/root]`; pnpm store v11 8.5 GiB pre-prune
  → 1.2 GiB post-prune; `~/.rustup` 25 toolchains / 33G; df ~62G free
  after the first sanctioned runs
