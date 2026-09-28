---
type: Design
title: Adopt a standalone checkout into the archive — custody before deployment
description: A receipt-driven, source-read-only design for importing legacy Git work, verifying custody, and handing deployment and retirement back to the operator.
resource: /design/archive-migration/draft0-syn2.gpt6sol.md
tags: [compfuzor, archive, migration, adopt, jj, dl]
status: draft
generated: { by: model:gpt6sol, at: 2026-09-27 }
stale_after: 2026-11-27
sources:
  - id: production-walkthrough
    resource: /design/archive-migration/draft0.glm53.md
    title: Production dl walkthrough and rescue count
  - id: fixture-analysis
    resource: /design/archive-migration/draft0.gpt6sol.md
    title: Fixture-tested failure modes and operator walkthrough
  - id: first-synthesis
    resource: /design/archive-migration/draft0-syn.glm53.md
    title: First synthesis and proposed adopt contract
  - id: legacy-transport
    resource: /script/deprecated-harvest-legacy-repo.sh
    title: Deprecated cross-checkout harvest implementation
  - id: toolkit
    resource: /archive/README.md
    title: Current archive toolkit contract
---

# Adopt a standalone checkout into the archive

## Situation and decision

Compfuzor can already refresh a canonical jj-colocated checkout at
`~/archive/<org>/<repo>` and deploy a symlink to it. It cannot yet *take
custody* of a pre-existing standalone checkout. The exemplar is `~/src/dl`:
its detached HEAD is 374 commits ahead of its locally recorded `github/main`,
while [`dl.src.pb`](/dl.src.pb) selects `main` in `~/archive/rektide/dl`. A
fresh clone and a new symlink would not protect that detached line, dirty work,
or application state. The [production walkthrough](/design/archive-migration/draft0.glm53.md#walkthrough)
imported three recovery refs; the [fixture study](/design/archive-migration/draft0.gpt6sol.md#evidence-read-only-specimen-and-an-isolated-migration)
showed why importing *some* refs and getting a healthy jj status do not yet
constitute a safe migration.

**Decision:** make `adopt` a one-time, plan-first **Git source custody** command,
not an alias for `refresh`, a deployment command, a database copier, or a
retirement command. It emits a durable receipt against which an independent
`verify-adoption` command checks actual objects, refs, bundles and exceptions.
Publishing any refs and changing the runnable checkout require separate human
decisions. Do not repeat the existing production import merely to try this
design: the existing refs and bundles are evidence to inspect, not targets to
replace.

An implementation investigation can ask: *Can a read-only inventory of the old
checkout and a private staged Git snapshot yield a complete, immutable recovery
set, with a receipt that still verifies when the old checkout is gone?* That
question is narrower, and more testable, than “automate the whole migration.”

## What the evidence actually says

- On 2026-09-27 the legacy `dl` HEAD was `c2ed963…`, `github/main` was
  `e9c7c40…`, and `git rev-list --count github/main..HEAD` returned **374**.
  The imported `harvest/dl-legacy/head` points at that HEAD. This is **not**
  evidence that no other remote ever had those commits: it is a count against
  a particular locally recorded ref. Legacy `origin` is Tangled; the archive
  playbook's declared `origin` is GitHub. Remote *names* cannot establish a
  shared baseline.
- The legacy working-copy ref captured 13,237 paths, **13,233 under `.jj/`**;
  a fixture reproduced the same selection problem on a small `.jj/`
  placeholder. An ephemeral `core.excludesFile` hid that *untracked* `.jj/`
  from the fixture, not tracked paths. Actual `dl` tracks
  `.beads/.beads-credential-key` and `.data/*.db-wal`; the key exists in
  commit `05190fb…`, which is reachable from the archive's locally recorded
  `origin/main`. Ignoring those paths now cannot retract them from history.
  This design neither prints their contents nor assumes their current validity.
- On a fixture retry, the old script force-updated the working-copy ref
  (`d686612…` → `3d496be…`) despite an identical tree. The script's two
  pre-harvest `--all` bundles exclude the synthetic commit created *after*
  bundling, and ignored DBs are in neither Git bundle. A failing `jj git
  export` is logged and ignored; `git add -A` failure is ignored too. Passing
  `health` after these operations proves neither completeness nor privacy.
- **Additional isolated fixture:** in
  `.test-agent/archive-migration/fixture-gpt6sol/source-write-probe/`, `git
  add -A .` with `GIT_INDEX_FILE` set to a separate path increased the source
  repository's loose-object count from **2 to 3** and left an untracked file's
  blob readable from its object database. Its worktree and ordinary index were
  unchanged. Thus “temporary index” does **not** mean “read-only source”; the
  old shell script also calls `jj git export` on the legacy checkout when a
  `.jj/` is present. The new command must not make that promise while using
  either operation on the source.

## Scope: three separate permissions

| Operation | May change | Must not change |
|---|---|---|
| `adopt` plan (default) | Nothing; optional private scratch for computations, cleaned deliberately | Source checkout/ODB/jj state; destination refs/worktree; remotes |
| `adopt --apply` | Private custody artifacts, destination object store and **new immutable recovery refs**; create destination if absent | Source checkout/ODB/jj state; existing recovery refs, selected `main`, destination checkout files, global shim, runtime DBs, remote server |
| Publish / deploy / retire | Only after independent authorization in their respective tools/manual procedures | Never implicit in `adopt` or verification |

If the destination already exists, `adopt` must not call `refresh` as a
convenience: even `refresh --update false` snapshots its worktree, imports
refs and can add missing remotes ([`refresh.ts`](/archive/src/refresh.ts)). If
the destination does not exist, apply may compose the existing clone with
`--update false` semantics *after* a read-only plan, but must explicitly
report checkout creation and recheck state before ref writes. No shallow
clone for custody unless coverage of missing parents is demonstrated. An
archive whose main worktree is busy or whose jj health fails is a preflight
stop, not something adoption heals or reconciles. Destination remote mismatch
is a review stop; never copy the legacy's remote URL into the archive just
because both call it `origin`.

The source-side contract is stronger than the shell script's: inspect Git
using read-only commands (disable optional Git index locks where applicable),
and construct any dirty-tree commit in an **isolated object store/index** with
read access to source objects. Do not run `jj status`, `jj git export`, `git
add`, or `git commit-tree` *against the source* under a “read-only” claim;
filters, submodules, symlinks and race conditions also need explicit tests.
If source jj-only work needs export, make it a separate, explicitly authorized
source-side preparation with its own backup, then re-plan. Distinguish a
malformed `.jj/` placeholder from a valid jj repo, but never infer “no
jj-only work” just because an inspection command failed.

## Proposed CLI and its evidence model

```text
archive adopt --legacy DIR --dest DIR --repo URL --branch main \
  --label dl-legacy [--exclude-from FILE] [--json]           # read-only plan
archive adopt --legacy DIR --dest DIR --repo URL --branch main \
  --label dl-legacy [--exclude-from FILE] --apply [--json]   # re-plan, compare, import
archive verify-adoption --receipt FILE [--legacy DIR] [--json]
```

I prefer **top-level `verify-adoption`** to `adopt verify`. It names a
read-only operation alongside the toolkit's existing top-level `health` and
`remotes`, avoids assuming nested Gunshi subcommands, and can consume a
receipt **after the source path has been renamed or retired**. `adopt verify
--legacy ... --label ...` has no immutable description of what the old path
contained at import time. `verify-adoption` must not say “safe to delete”;
its optional `--legacy` adds source drift and retirement *preflight* checks.
The receipt and destinations suffice to verify Git custody without it.

### Plan: name what exists, name what will be absent

1. Canonicalize both paths; ensure they are distinct, not nested, and inspect
   alternate Git worktrees (`.git` can be a **file**), bare/shallow/partial
   clones, sparse checkouts, LFS pointers, submodules, alternates and local
   object integrity. Scope v1 to ordinary complete Git checkouts if any of
   these cannot be covered; fail with a named reason, not a partial success.
   Inspect archive health and declared-vs-actual URL without changing either
   repository. Hold writers still through apply or detect drift and abort.
2. Inventory **all** source custody candidates, not only local branches and
   a detached HEAD: `refs/heads/*`, HEAD, tags (including annotated tag
    objects), stash, notes, replace and nonstandard refs. Inspect reflog-only
    tips (including older stash entries) and dangling objects as separate
    potential work: `git bundle --all` does not make unreferenced/reflog-only
    work durable. Pin wanted tips or record an owner's disposition; do not
    claim every dangling object is a wanted commit. A source ref not selected
    for protected transfer is an explicit unresolved item; the bundle alone
    is not a silent substitute for the missing named ref. Identify staged
   vs unstaged changes, deletions, untracked files, ignored files, and an
   exact proposed working-copy tree. Git's single synthetic tree cannot
   reconstruct separate index and worktree states; report that loss of
   structure, or preserve both as separate snapshots when required.
3. Deny `.git`/`.jj` internal paths in the dirty-tree snapshot, including
   through nested paths; report them as source metadata needing separate
   custody. Honor ordinary ignore rules and an explicit exclusion list for
   **untracked** input, but show tracked exceptions, even if ignored/excluded.
   Stop on unexplained private/transient included paths, unresolved index
   entries, filters that cannot be reproduced, or vanished/changed files.
   Do not claim to detect every secret or label every `.data` file expendable.
4. State the baseline for every count. Lead with the striking fact, but label
   it accurately: **“374 commits in legacy HEAD not reachable from its
   recorded `github/main` at inspection”** for the dl specimen; do not
   universally print “374 unpushed commits rescued.” Separately report
   deduplicated commits reachable from proposed source tips but **not** from
   pre-import destination protected refs; source vs destination may already
   overlap. “Unpushed” requires an explicitly selected, freshly validated
   remote tip (or remains `unknown` if remote authority/reachability is
   unclear). Preserve the exact tip OIDs and baseline OIDs beside counts;
   handle diverged/rewritten branches and unavailable shallow ancestors as
   unknown/blocked, never as zero. Branch and dirty-file counts are likewise
   measured against a recorded snapshot.
5. Present a **left-behind inventory**: ignored state, tracked runtime-like
   paths, valid/unresolved jj state, excluded paths, stash or refs not covered,
   source consumers (global shim, services, symlinks), and backup custody.
   Paths and classifications only; no credential values or ignored-file
   contents in logs/JSON. Give *application-aware* state handoff guidance,
   not an “exact `cp`” for a potentially live SQLite DB/WAL set.

Plan output should have structured `blockers`, `warnings`, proposed ref
mapping, baseline OIDs and unresolved custody items. JSON is one result on
stdout; failure and policy diagnostics use stderr, consistent with the
[existing CLI contract](/archive/README.md#compfuzor--ansible). The plan
must identify its freshness assumptions; apply re-inventories, checks the
source/destination fingerprints and excludes, and stops on drift rather than
importing a later tree under an earlier assertion. Plan need not persist a
token or lock, but apply must output its final plan/receipt before claiming
success.

### Apply: protect objects before announcing success

Stage proposed source tips and deterministic synthetic commits in private
storage **outside both checkouts**. Fingerprint a working-copy snapshot by
parent commit, tree OID and snapshot format; use fixed commit metadata if a
Git commit is needed so an unchanged retry gets the same OID. Stage a
**self-contained bundle covering *all* proposed tips, including the synthetic
commit**, and verify its heads and object closure from a fresh repository
before installing refs. Preserve a private pre-write destination bundle if
destination refs might change. If a post-import bundle is also made, it is
additional audit evidence, not the first backup of the synthetic commit.
Bundles contain Git objects only: no `.jj` operation log, ignored DBs, or
runtime backup. Store bundles/receipt with restrictive permissions and record
SHA-256 checksums and verified head OIDs; a checksum detects corruption but
does not supply independent/off-host custody.

Map source refs into **typed, collision-free** archive names. A human label
such as `dl-legacy` is a suggested default when deployment `NAME=dl` is
known, not a requirement on unrelated repositories. Put commit-valued
branch/HEAD/working-copy pins under `refs/heads/harvest/<validated-label>/`
with respective `branch/<encoded-source-name>`, `head/<OID>` and
`working-copy/<parent>-<tree>-<format>` lanes. Preserve annotated tag **tag
objects** under `refs/tags/harvest/<label>/<encoded-source-name>`; keep stash,
notes and other non-branch refs under a distinct protected
`refs/adopt/<label>/<encoded-full-ref>` lane, not under `refs/heads/`. A Git
branch ref cannot point to an annotated tag object: a further scratch check
in the source-write fixture rejected `git update-ref refs/heads/… <tag OID>`
but accepted `refs/tags/… <tag OID>`. The receipt maps each original name and
type to its destination name; validate encoding, length, ambiguity, OID type
and Git refname legality before writing. The *existing*
`harvest/dl-legacy/{main,head,working-copy}` refs belong to the old import:
**never overwrite or silently reinterpret them**. Different new source tips
under an occupied branch name require a new label (or a new explicit
generation), not a forced update; identical OID + mapping means no-op.
Content-addressing the dirty-tree ref avoids timestamp proliferation but
does not solve mutable branch-tip collisions. Typed lanes also avoid a
source branch literally named `head` or `working-copy` colliding with
special snapshots.

Import objects into the archive, then install the ref set with expected-old
values / no-overwrite semantics, checking concurrent changes at the point of
publication. Never `git push +` to recovery refs. Write an atomic private
receipt describing source path at inspection, source Git identities, excluded
paths, exact source OIDs and tree, remote-baseline provenance, destination
pre-state, immutable ref mapping, bundle locations/checksums, checks and
unresolved items. If an import is interrupted after some refs are installed,
resume by matching the receipt/staged evidence or stop for inspection;
**never reset** refs merely to make a rerun clean. Report `complete` only
after `verify-adoption` confirms refs, trees and bundles. Fixture-test jj
visibility and destination `health` after ref import; jj health alone is not
the verification criterion.

### Verify, handoff, and publication

`verify-adoption` checks every receipt OID against archive refs and objects,
tree path inventory against the captured manifest, bundle checksum and
independent restore/readability, and archive jj health. If the source still
exists, compare current source fingerprints with recorded ones and report
**drift**, not a false failure of the historical import. Separately report
remaining jj-only revisions, ignored state, consumer paths/shim target,
unresolved LFS/submodule state, and independent-backup evidence as retirement
blockers or unknowns; none of these are “solved” by a successful Git import.
No automatic deletion, cleanup, or ordinary wildcard push.

**Credential key = concrete publish gate, not an excuse to reject local
custody.** The tracked `.beads/.beads-credential-key` is in historical Git
objects reachable from the locally recorded archive `origin/main` already.
Local imports/bundles should therefore be private, not refused: they preserve
evidence, including unpleasant evidence. Before any *new publication of
adoption refs* to *any* remote, require owner authorization after review of
the full reachable history, current trees, exposure/rotation status, remote
policy and which exact refs would become reachable. Rotation/revocation of an
active key is an incident response, not something this command can certify or
undo by declining a push. Do not imply a gate on only newly captured dirty
files makes already published history safe. A later publishing interface, if
one exists, must select explicit refs and destinations; v1 `adopt` has **no
publish flag**. Local bundle custody is also privacy-sensitive: do not place
bundles in public deployment paths or log their contents.

## Manual dl tail and README presentation

After a verified import, source custody still does not choose the runnable
line. Review whether `main` or the detached work is the desired deployment
base; [`dl.src.pb`](/dl.src.pb) currently chooses `main` and builds/links the
**archive main worktree**, which may be affected by `refresh` reconciliation.
The [workspace premise](/design/archive-deployment-premise/draft0.glm53.md)
proposes separating deployment workspaces; do not bake that unresolved choice
into adoption. Hold writers, make a consistent application-specific backup
of ignored DB/WAL state, restore it under dl's rules if continuity is wanted,
then run the playbook with `-i 'localhost,' -c local -e USERMODE=True` only
when source and deployment choices are settled. Validate the **target** of
the pnpm global shim, not only `command -v dl`; keep the legacy checkout as
a rollback target until the link and state work. Renaming/parking and eventual
disposal require a separate retention and consumer check. A symlink is not
retirement authorization.

I agree the [archive README](/archive/README.md) needs a flagship “migrate a
standalone checkout” example: lead with the **374-commit baseline and actual
capture**, then show plan → apply → receipt verification → human deployment
and state handoff → deliberate retirement. Keep it concise, avoid turning a
case study into a promise that every migration is one command, and link to
the full runbook. The README should say the existing dl import already
happened; the new example is not a command to overwrite those refs.

## Decisions still requiring the operator, and implementation boundaries

- **Legacy jj:** default-block valid `.jj` with unproven Git coverage; request
  explicit source-side export/pinning and a new plan. Define read-only
  inventory tests for colocated jj (including invisible/unexportable heads)
  before automating any exception. An inert `.jj` placeholder can be
  acknowledged and excluded; an inspection failure is not such evidence.
- **Backup/retirement:** require a verified independent backup or continued
  legacy source retention before recommending retirement. Whether off-host
  storage is mandatory is the owner's durability policy; `verify-adoption`
  reports evidence/absence and never grants disposal permission.
- **Publication:** default no push, including no suggested wildcard command;
  record declared GitHub vs Tangled endpoints and require separate remote/ref
  choice and history/credential review. The key already present on recorded
  `origin/main` calls for owner-led exposure and rotation review now, not a
  promise that blocking a future push repairs the past.
- **History formats:** define v1 admission rules for sparse/shallow/partial
  checkouts, tags/stash/nonstandard refs, LFS and submodules; if coverage
  cannot be proved, block or explicitly leave a recorded unresolved item.
  The old script's “branches + detached HEAD + dirty tree” is not a general
  completeness guarantee.
- **Workspace and state:** deployment workspace selection and dl's possible
  move of runtime state out of source checkouts are separate decisions.
  Adoption reports both; it neither chooses `main` nor moves state.

## Implementation brief and acceptance evidence

This is ready to become a **bounded implementation brief for Git custody**,
not for automatic end-to-end conversion. Specify: read-only inventory/admission
matrix; stable receipt schema and private artifact location; isolated snapshot
and self-contained bundle creation; immutable ref namespace and retry protocol;
top-level CLI help/JSON; verification independent of the source path; and
explicit privacy/remote and deployment handoff. Implement/test the receipt
and verifier together: otherwise “apply succeeded” is unverifiable.

Disposable Git+jj fixtures should cover: the 374-style detached divergence
with a separately selected remote baseline; dirty tracked/untracked and
ignored DBs; tracked key-like path; valid jj-only and invalid `.jj/` cases;
staged/unstaged distinction; source branch `head` and `working-copy`;
annotated tags/stash/reflog-only commits; ref race/collision, unchanged retry and changed retry;
interruption at object transfer/ref installation/receipt write; bundle-only
restoration including synthetic commit; source ODB/index/worktree unchanged
byte-for-byte; destination worktree unchanged; and verification after the
legacy path is moved. Also test the source-launcher and committed bundle
paths as required by the [toolkit build contract](/archive/README.md#build-checks-tests).

## Cross-references

- [Ghost-head incident](/design/repo-jj-archive/incident-ghost-heads.glm53.md): explains why jj health catches missing visible commits but cannot substitute for protected Git ref/object coverage.
- [Archive toolkit follow-up](/design/repo-jj-archive/draft1.gpt6sol.md): defines the landed command boundary and the existing `refresh`/`health` behavior that adoption must not quietly broaden.
- [Deployment workspace premise](/design/archive-deployment-premise/draft0.glm53.md): the pending decision that prevents treating an imported detached HEAD as the runnable archive main worktree.
- [Current transport](/script/deprecated-harvest-legacy-repo.sh): reference for backwards compatibility and the forced-ref, pre-bundle, temporary-index and export-failure hazards that need regression tests.

## Deltas from draft0-syn.glm53.md

- **Kept** plan-first, permission separation, numerical headline, suggested
  `NAME`/`NAME-legacy` labels, content-identified dirty snapshots and README
  story; **qualified** “unpushed” by naming the exact baseline and split
  import-specific counts from remote-publication claims. A good headline
  must still be true when remotes diverge or are stale.
- **Replaced** `adopt verify --legacy --label` with receipt-based top-level
  `verify-adoption`; verification must survive renaming/retiring the source.
- **Strengthened** the source read-only promise using a new temporary-index
  fixture result; isolated staging and a verified pre-import **complete**
  bundle protect the synthetic commit before refs change, rather than
  depending on the synthesis's post-import bundle to close a gap.
- **Expanded** coverage beyond three refs to inventoried Git refs, stage/index
  semantics and typed collision-free names; immutable branch refs require a
  new generation when changed, not merely a content-addressed worktree name.
- **Narrowed** the credential review to a hard gate on *future publication*,
  plus private local custody and owner-led response to existing exposure.
  Dropped generic exact DB copy commands and any implication that healthy jj
  or a passing bundle check can certify runtime-state migration/retirement.
