---
type: Status
title: config-user-target design — handoff and state of play
description: Historical pre-build handoff for the tri-state drift/config design; current consumer-toolkit implementation is indexed in this directory's README.md.
resource: /.design/config-user-target/status.glm53.md
tags: [compfuzor, config, targets, drift, handoff, zim, mise, block-in-file]
status: deprecated
generated: { by: model:glm-5.3-max, at: 2026-09-08 }
verified: { by: unverified }
stale_after: 2026-10-08
sources:
  - id: current-design
    resource: /.design/config-user-target/draft3.solx.md
    title: Strategy toolkits for targets, drop-ins, and global bins (authoritative)
  - id: prior-design
    resource: /.design/config-user-target/draft2.solx.md
    title: Scoped targets and assemble-into-user configs
  - id: brief
    resource: /.design/config-user-target/brief.glm53.md
    title: Binding human decisions D1-D4 and constellation pointers
---

# config-user-target: handoff explainer

> **Historical checkpoint, superseded by the consumer-toolkit build.** Start
> with the [current index](/.design/config-user-target/README.md),
> [user workflow](/doc/config/consumer-toolkit.md), and
> [latest implementation checkpoint](/.design/config-user-target/build4.solx.md).
> The human reopened the architecture after this handoff. The implemented
> default is linked donor drop-in files plus local assembly, with whole-config
> copy/link alternatives. The draft3 authority, locked rollout, and outstanding
> implementation plan below describe the earlier state—not instructions to
> replace or duplicate the implementation now present. The original incident
> and decision history are preserved below.

Written for fresh sessions (human or agent) picking this work up mid-stream.
Read order: this doc, then **draft3** (authoritative design), then draft2
(detail retained by draft3), then `brief.glm53.md` (the human's binding
decisions in their own terms).

## The story in one paragraph

The human couldn't tell what "drift" meant across their compfuzor
deployments (zim/mise shell config especially). Investigation revealed a
**tri-state**: *would-run* (what config assembly would produce now) /
*materialized* (the committed output in /etc/opt) / *user* (copies embedded
as managed blocks in ~/.zshenv, ~/.bashrc, etc.). Two primitives were built
to make all three states streamable, a four-round design effort (sol/GPT-5.6
xhigh) turned that into a full **install-and-status target declaration**
system, and the design is now implementation-ready modulo six open decisions.

## The inciting incident: mise & zim (Sep 4–7, 2026)

This design effort did not start from abstraction. It started from a live,
confusing debugging session on this machine's shell setup. The timeline:

- **Sep 4**: zim was split into two channels — `zimrc` (interactive, loaded
  from `.zshrc`) and `zimenv` (early, loaded from `.zshenv`) — each an
  independent zimfw install (`~/.cache/zim`, `~/.cache/zim-env`) fed by its
  own assembled config. Mise's zsh activation was moved out of mise.opt.pb
  into the `rektide/zim-mise` module, loaded once via the zimenv channel
  (full activation interactive, shims otherwise).
- **Sep 5**: the `mise-user-env` systemd bridge (which pushed `mise env`
  into the systemd user environment as an ambient channel) was disabled —
  two competing env channels was the root confusion (commit `kzkrvlvlywzx`).
- **The debugging residue** (still visible when this effort began): bisect
  breadcrumbs `echo HI1/HI3/HI4` in `~/.zshrc` — **HI2 was never found and
  never followed up**; two leaked `.config-candidate.*` temps in
  `/etc/opt/zim-main` from interrupted config runs; a stale-mtime scare
  where re-assembling `zimrc` made `~/.cache/zim/init.zsh` "drift" by
  timestamp; and a `status.sh` crash (`ZIM_CONFIG_FILE: unbound variable`)
  caused by an ambient exported `DIR` making generated bins source another
  deployment's `env.export`.
- **The question that started everything**: "I don't know what the drift
  is" — which layer? fragments → assembled → zimfw-built → user startup
  files → mise settings? Answering it produced the tri-state vocabulary,
  `block-in-file --read`, `config.sh --stdout`, and then the whole design
  corpus.

**Where mise & zim sit in the design** (they are the first consumers, not
afterthoughts):

- **mise** — first ETC_FILES `targets` consumer: its `.bashrc`/`
  .bash_profile` blocks (with `BASH_RC`/`BASH_PROFILE` env selectors) become
  declared `strategy: block` targets; the hand-written
  `install-bash-user.sh` is deleted (draft1 "Mise migration", retained in
  draft3 commit 14). Its zsh side stays owned by the zim-mise module —
  deliberately NOT re-imported.
- **zim** — the deepest consumer. Option B locked: user-owned copied zimrc
  (`ZIM_CONFIG_FILE`, copy default / link available) + link-only
  `zimfw.conf` registry; contributor host discovery must resolve through
  the registry (draft3 "Host discovery"). The startup loaders stay ETC_FILES
  and must **never** become CONFIGS targets — they are different documents
  from the config outputs (draft0's boundary finding). `install-config-
  user-dropins` delivers canonical fragments into `~/.config/zsh/zimrc.d/
  compfuzor`; the staged end-state composes both poles (pieces delivered by
  Pole A, user file assembled by Pole B, aggregate copy retired at cutover).
  zim's authored `status.sh` still masks the generic STATUSES orchestrator
  and still has the unbound-variable bug — both fixed in draft3 commit 14.

**Outstanding mise/zim cleanup from the original incident** (unclaimed):
the HI markers in `~/.zshrc`, the leaked config-candidate temps, legacy
pre-channel-split artifacts in `/etc/opt/zim-main` (flat `zim/*.conf`,
`zim-disabled/`, `zimfw/`, `zimfw.conf`, `zim.zsh`), and stale mise-main
files (`mise.zshrc`, `mise.zprofile`, `mise-user-env.service`, old install
bins).

Live state as of Sep 7: **both subsystems fully converged** — every drift
surface green (see verification block below).

## Shipped and live (not design — working code)

| What | Where | Commit |
|---|---|---|
| `block-in-file --read` — byte-exact managed-block extraction (markers + provenance excluded, exit 1 when missing, pure stdout) | `~/src/block-in-file` (global CLI links to its dist) | `61ae6db`, beads `bif-read` closed |
| `config.sh --stdout` — streams the would-be assembled config byte-exactly | compfuzor `files/config-run.sh`, deployed to /opt/zim-main | `ddab0db6` |
| USERMODE dir-root fixes (cache `/.cache` bug; log/spool var↔fsh.py disagreement; stray `/var`; trailing slashes) | compfuzor `vars/common.yaml`, `vars/common.user.yaml` | `a2273461` |
| `diff3` three-way demo + drift injection proofs | scratch (tmp-opencode), reproducible from this doc's examples | — |

Live system state (verified 09-07): zim + mise fully converged — zero drift
across all surfaces (fragments→assembled, assembled→built init.zsh,
generated→user block copies). The one live incident feeding the design:
`/usr/local/bin/jj` is a **dangling symlink** into a cleaned
`/usr/local/src/jujutsu-git/target/release/jj` — link-installed bins break
silently when sources move. This is the motivating case for copy-default
bins and dangling-link status.

## The design corpus (`.design/config-user-target/`)

- **draft0.solx.md** — status-only proposal; surveyed compiler/runtime seams.
- **draft1.solx.md** (`1167e761`) — install-driving `user_targets`,
  block/symlink/copy strategies, ETC_FILES extension, exit-4 semantics,
  config-remote rollback coordination, safety preflights.
- **brief.glm53.md** (`825df375`, corrected `5af97bbd`) — the human's binding
  deltas D1-D4 + constellation pointers. **D1 correction matters**: cmp
  decides drift, diff3 only displays — an earlier "parse diff3 headers"
  instruction was a misread and is retracted in-place.
- **draft2.solx.md** (`93740a3d`) — two poles (deploy-down vs
  assemble-into-user), scope + dir classes, drop-in dirs, evidence sidecars,
  additive blocks, system privilege lane.
- **draft3.solx.md** (`f5202d38`) — **AUTHORITATIVE**. Strategy toolkits
  with defaults, bypass at generation+runtime, global bins as a delivery
  surface, Zim Option B topology, config-input fan-out drop-ins, 16 ordered
  implementation commits.

Design conductor: sol (GPT-5.6 Sol xhigh), session
`ses_f813cf6d0ffe280pKVy9eQeJb2`, four rounds in one continuous
conversation — **that session holds the full design context** and can be
resumed.

## Locked decisions (do not relitigate)

1. Public field: **`targets`** (scope-neutral; `user_targets` renamed away).
2. Comparison: **pairwise `cmp` decides** (`--threeway` bits 0/1/2/3;
   operational failures exit 4); **diff3 is display-only** for humans.
   Reporters collapse to canonical 0/1/2.
3. Install: targets apply **post-commit**, attempt-all, aggregate-fatal
   exit 4, outputs never rolled back; `config-remote.ts` keeps its input
   mutation on post-commit failure.
4. Zim: **Option B** — user-owned copied zimrc (`ZIM_CONFIG_FILE`, copy
   default, link available) + link-only `zimfw.conf` registry; contributor
   host discovery resolves through the registry, never the runtime copy.
5. Scope: `user|system`; system effects via a **separate privileged lane**
   (Ansible become / manual install.sh); `config.sh` never escalates.
6. Strategy toolkits: `strategies: {default, available}` with `[copy, link]`
   for whole-file (copy built-in default); **block is fixed and
   non-interchangeable** (whole-file variants of aggregate files would
   destroy unmanaged content). Direct tools `compose: false`; only the
   dispatcher joins install composition. Runtime selectors
   `COMPFUZOR_<SURFACE>_STRATEGY`; bypass at generation (no bin emitted)
   and runtime (unit guards via existing bin_disarm/guard machinery).
7. Dir roots: consumer-facing class table is **XDG**; internal USERMODE
   staging stays FHS-mirror; both stand (draft3 §"Dir-class roots").
8. User paths resolve at **runtime** for the invoking user (HOME/XDG/env
   selectors, structured `{env, default, suffix}`, no `eval`); ambient
   `DIR` must be distrusted by generated bins.
9. No automatic pruning — removing declarations never removes destinations.

## OPEN QUESTIONS (the six, with recommendations)

Presented to the human 09-08; not yet answered (UI prompt dismissed —
fatigue, not rejection):

1. **Consumer dir roots**: user log `${XDG_STATE_HOME}/log` (rec) vs
   `~/.local/var/log`; system share `/usr/share` (rec, matches SHARES_DIR)
   vs `/usr/local/share`.
2. **Evidence sidecars** for direct-pole configs: **opt-in** (rec) vs
   automatic. (Sidecar = last-applied managed-block projection; it
   distinguishes "inputs changed since apply" from "user edited managed
   blocks" when slots 2/3 co-reside. draft3 explains fully.)
3. **Recurring link users**: env selector / playbook default only (rec, v1)
   vs persistent per-user preference file.
4. **Status semantics**: any healthy *available* strategy = clean (rec;
   status reports which is present) vs healthy-nondefault = drift.
5. **Block variants**: keep block fixed (rec; question 6 in draft3 overlaps
   locked decision 6 — treat as settled unless the human reopens).
6. **Zim managed drop-ins**: populate `~/.config/zsh/zimrc.d/compfuzor` now
   as preparation (rec) vs defer until the direct-pole assembler consumes
   it.

## Implementation (once questions answered)

draft3 §"Ordered implementation commits" lists 16 slices. Suggested
grouping: (a) schema + dispatcher + bypass (commits 1-4); (b) global bins +
Rust/jj tracer bullet (5-8); (c) target toolkit integration + fan-out
(9-10); (d) Zim B + timing tests + drop-ins (11-13); (e) retained
migrations: mise blocks, jujutsu conf.d, zim status.sh rename/unbound-var
fix (14); (f) direct pole + clickpad (15); docs (16). Mise remains the
first ETC_FILES consumer; jujutsu conf.d the first drop-in consumer.

## Session logistics a newcomer needs

- **jj is broken on this machine**: `/usr/local/bin/jj` dangles at the
  cleaned jujutsu build. Commit via **git in the colocated repo** (jj
  auto-imports once rebuilt; rebuilding jj is also draft3 commit 8's tracer
  bullet). Do not push.
- compfuzor has unrelated uncommitted working-copy changes predating this
  effort (`files/config-remote.ts`, `library/filter_plugins/config_compile.py`,
  `termctrl.src.pb`) — commit explicitly by path, never `jj commit` bare.
- Generated compfuzor bins default `$DIR` from the **ambient environment**;
  a foreign exported `DIR` makes them source the wrong `env.export` and die
  under `set -u`. Export `DIR=/opt/<name>-main` when invoking bins directly
  (this is also a design input: draft3's distrust-ambient-DIR rule).
- block-in-file is first-party (`~/src/block-in-file`, gunshi/vitest); its
  global CLI symlinks into the repo `dist/`, so building there changes the
  live tool immediately.
- Beads: compfuzor uses bd; block-in-file repo has its own AGENTS.md
  demanding `git push` on session end — the human's global rule overrides:
  never push.

## Verification quick-reference (all should be green)

```sh
export DIR=/opt/zim-main
/opt/zim-main/bin/config.sh --check -q          # rc 0
ZIM_CONFIG_FILE=/etc/opt/zim-main/zimrc /opt/zim-main/bin/status.sh  # silent, rc 0
block-in-file --read -n zim-main-zimenv ~/.zshenv | diff - /opt/zim-main/etc/zimenv.zsh  # identical
/opt/zim-main/bin/config.sh --stdout zimrc | diff - /etc/opt/zim-main/zimrc              # identical
```
