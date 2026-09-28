---
type: Review
title: Archive custody safety review — inventory and acquisition checkpoint
description: Independent safety review of Git custody inventory, source-read-only boundaries, path acquisition, and admission against the custody brief and toolkit direction.
status: draft
generated: { by: model:gpt6luna, at: 2026-09-28 }
sources:
  - id: brief
    resource: /design/archive-migration/brief0.gpt6sol.md
    title: Git custody implementation brief
  - id: direction
    resource: /design/archive-toolkit/direction0.gpt6astra.md
    title: Archive toolkit implementation direction
  - id: contracts
    resource: /design/archive-toolkit/custody-contracts0.gpt6sol.md
    title: Archive adoption custody contracts
  - id: core-review
    resource: /design/archive-toolkit/core-review0.glm53.md
    title: Core custody/recovery safety review
---

# Safety review checkpoint: inventory and source acquisition

## Scope and verdict

This review reads the implementation against the [custody brief](/design/archive-migration/brief0.gpt6sol.md), [accepted toolkit direction](/design/archive-toolkit/direction0.gpt6astra.md), [custody contracts](/design/archive-toolkit/custody-contracts0.gpt6sol.md), and [earlier core review](/design/archive-toolkit/core-review0.glm53.md). The direction and core-review files are in `design/archive-toolkit/`, not `design/archive-migration/`.

The current read-only plan is **not safe to expose as a source-read-only operation** yet. Two concrete blockers are reproduced below: canonical-path aliases can route apply writes into the source, and Git's local filter/fsmonitor hooks can execute during inventory even when the eventual plan is blocked. The dirty-path proposal also reads through symlinks and cannot represent a dirty symlink correctly. Findings are from code reading plus isolated fixtures under `.test-agent/custody-review-luna/`; no production checkout was used.

This is an initial checkpoint. The follow-up review of apply/retry/ref transaction, vault durability, and verifier gates is still in progress; findings below should be acted on independently rather than waiting for that extension. Absent-destination support is intentionally blocked in this implementation slice and is not a finding. The known cancellation issue is excluded.

## Findings

### H1 — Canonical source/destination aliases bypass separation and write into source

**Blocker.** `resolvePaths()` compares only the operator-provided strings (`archive/src/custody/inventory.ts:132-140`). Later, source and destination probes independently resolve their paths (`inventory/probe.ts:368-415`, `1291-1303`), but no check compares those canonical roots. A symlink alias therefore passes the distinct/nested check while source and destination resolve to the same repository.

I reproduced this with a clean jj-colocated fixture and `dest` as a symlink to `legacy`: the plan returned `state: "ready"` with identical `identity.legacyRealpathAtCapture` and `identity.destinationRealpath`. Applying that ready plan routed destination object import back into the same Git ODB. It then failed a later replan with `candidates-unclassified`, but the source ODB already had two new packs (six new pack/index/reverse-index files). The write happens at `apply.ts:502-503` (`importBundle` and `importReceipt`) before the next source recheck at `505`; the later blocker cannot undo the source mutation.

**Minimal regression:** create a clean Git source with a matching `origin` and `.jj`, symlink a different destination spelling to it, and assert plan blocks before any stage. For a fixture-only apply probe, fingerprint `source/.git/objects` before/after and assert no change. The existing scratch reproduction is `plan-alias-probe.mjs` / `apply-alias-probe.mjs`.

**Minimal fix:** canonicalize both existing roots before admission and repeat same/nesting/alias checks on the realpaths; fail before returning a ready plan. Apply should independently reassert source and destination Git common dirs/object directories are disjoint before any transfer, not rely only on later fingerprint drift.

### H2 — Read-only Git inspection executes repository-local commands

**Blocker.** `gitRead()` disables system/global config and optional locks, but repository-local configuration remains active (`archive/src/repository/git.ts:77-84`, `139-152`). `probeSource()` records a blocker for configured `filter.*` (`inventory/probe.ts:556-567`) but continues probing; `git status` runs later at `735-749`. Git invokes a configured clean filter while computing status. I ran a disposable plan with a clean filter that appends a marker file: the plan returned blocked with `source-filter-configured`, and the filter marker was nevertheless written. A local `core.fsmonitor` executable is not checked at all and also ran during `git status` in a separate fixture.

The eventual blocker is not a read-only boundary: a configured command can mutate the source, write elsewhere, or perform other side effects before admission fails. `gitRead`'s sanitized inherited `GIT_*` variables do not neutralize local Git config.

**Minimal regression:** configure a clean filter and a `core.fsmonitor` hook that each write a fixture marker; run plan and assert neither marker appears, including when the plan is blocked. Do not merely assert a blocker code.

**Minimal fix:** prevent these commands from running before status/probing can invoke them: either fail fast before any potentially executing Git query when unsafe local config is present, or explicitly disable all executable Git config paths for inspection and prove with fixtures that the chosen status/index commands cannot run filters, fsmonitor, or other local helpers. Inventory completeness must not be pursued by running a blocked command.

### H3 — Inventory follows symlinks outside the checkout; dirty symlink manifests diverge

**Blocker for the promised acquisition boundary; also a dirty-symlink support gap.** LFS scanning opens every tracked/index and selected untracked path with ordinary `open()` (`inventory/probe.ts:247-267`, `862-901`), which follows symlink targets, including absolute or `..` targets outside the source root. For dirty paths the proposed manifest uses `git hash-object --no-filters -- <path>` (`1102-1117`), which also reads through a symlink, while mode is separately classified as `120000` by `lstat` (`1121-1127`). Git staging preserves the symlink itself; the preview then compares against a different blob and blocks with `snapshot-preview-failed`.

In a fixture, an untracked symlink `source/link -> ../link-target` caused plan to block at snapshot preview; this confirms that the inventory's proposed symlink blob is not the symlink-target-text blob that the private stage creates. Independently, the unconditional LFS probe can open a tracked clean symlink target outside the source even though no such target bytes belong in Git custody. The stage's direct symlink tests (`archive/test/custody/stage.test.ts:216-245`) do not exercise this inventory path.

**Minimal regression:** cover a dirty in-root symlink, a dirty external symlink, and a clean tracked external symlink. Assert that in-root link text/mode is identical between proposal and stage; assert external targets are not opened/read and admission gives a named blocker if policy requires containment.

**Minimal fix:** use `lstat` before payload reads; never open a symlink for LFS probing. Compute mode-`120000` blob identity from `readlink()` bytes (not target contents), and apply the brief's root-containment policy without traversing targets. Ensure FIFO/device paths are also rejected or safely handled rather than opened as ordinary files.

### M1 — Ignored-path inventory is silently partial for ready plans

`probeSource()` obtains the ignored path listing, but stores only the first 512 paths (`inventory/probe.ts:826-847`) and emits a warning for the remainder. This can still produce a ready plan and receipt; the omitted names are not reconstructible from the aggregate `ignored-runtime-state` count at `849-853`. The brief calls for a complete inventory where inspection is possible and a named left-behind list, since these paths are precisely what an operator needs to review before source retirement.

**Minimal regression:** create more than `BOUNDS.ignoredListed` ignored paths including a clearly named DB/WAL or credential-like fixture near the end; assert either every name is represented or apply is blocked with an explicit incomplete-inventory status. A warning plus count alone is insufficient evidence of a complete left-behind inventory.

## Verification performed

- A source/destination alias plan returned `ready` with both canonical paths equal. A fixture-only apply was rejected after transfer, with source `.git/objects` gaining two packs before the replan failure.
- A clean-filter hook and a `core.fsmonitor` executable each ran during `git status` under a plan-style Git environment.
- A dirty untracked symlink plan failed at snapshot preview; code inspection shows unconditional LFS scanning follows tracked symlinks too.
- No broad suite rerun was performed. The reported passing inventory/stage/apply/verifier suites do not test these boundaries.

## Cross-references

- [Custody brief](/design/archive-migration/brief0.gpt6sol.md): requires canonical root separation, truly read-only source inspection, NUL-safe exact snapshot manifests, and symlink-safe acquisition.
- [Custody contracts](/design/archive-toolkit/custody-contracts0.gpt6sol.md): makes symlink containment and before/after source fingerprints explicit; it also describes inventory as including ignored/excluded paths.
- [Core review](/design/archive-toolkit/core-review0.glm53.md): earlier codec/ref fixes were read as prior art and are not duplicated here.

## Follow-up checkpoint

Next review slice: inspect current `apply.ts`, `recovery/git-ref-store.ts`, `vault.ts`, and `verify.ts` against receipt-first retry, exact baseline discounting, final drift gate, owner-only vault behavior, and independent verification. Commit any additions as a new revision rather than replacing this checkpoint.
