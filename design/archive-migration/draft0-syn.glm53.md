---
type: Design
title: Standalone-to-archive migration — synthesis of the draft0 wave
description: Synthesizes the glm53 production walkthrough and the gpt6sol fixture-tested safety analysis into one adopt design: plan-first, permission-separated, append-only, with the rescue-number headline.
resource: /design/archive-migration/draft0-syn.glm53.md
tags: [compfuzor, archive, migration, dl, jj, synthesis]
status: draft
generated: { by: model:glm53, at: 2026-09-27 }
stale_after: 2026-11-27
sources:
  - id: draft-glm53
    resource: /design/archive-migration/draft0.glm53.md
    title: production walkthrough draft (374-commit rescue)
  - id: draft-gpt6sol
    resource: /design/archive-migration/draft0.gpt6sol.md
    title: fixture-tested safety analysis and adopt proposal
  - id: toolkit
    resource: /archive/README.md
    title: archive/ jj toolkit
  - id: legacy-harvest
    resource: /script/deprecated-harvest-legacy-repo.sh
    title: deprecated bash legacy harvest
---

# Standalone-to-archive migration — synthesis

## What is up

Two independent draft0s addressed the operator's challenge: *standalone
working checkout → archive-managed is a core problem compfuzor solves for;
`dl` is the example; show the manual steps; improve the tool.* One ran the
migration live on production (`glm53`), one proved the hazards on fixtures
(`gpt6sol`). They converged on the workflow's shape and safety posture, and
each found what the other missed. This synthesis merges them into a single
adopt design and cross-compares the sources at the end.

The joint verdict: **the migration is possible today for Git-representable
history, with discipline; it is not yet a trustworthy one-command conversion.**
The destination is a plan-first `adopt` with permission separation.

## The problem, stated once

Compfuzor's archive premise wants one canonical jj checkout per upstream at
`~/archive/<org>/<repo>`. The world hands us standalone checkouts:
`~/src/dl` arrived with a detached HEAD on **374 unpushed commits**, a `main`
branch, remotes named `github` (GitHub) and `origin` (**Tangled**, not
GitHub), an experimental untracked `.jj/`, gitignored runtime DBs, *tracked*
`.beads/`+`.data/` state (including a credential key in history), and a pnpm
global shim. A clone of `main` would orphan the detached line; a naive
retirement would destroy months of work. Moving custody without losing
anything — and *telling the operator what was rescued and what was left* — is
the job.

## Evidence (merged, verified)

From the production walkthrough ([draft0.glm53.md](/design/archive-migration/draft0.glm53.md)):

- `refresh` cloned the canonical archive cleanly; `health` preflight passed.
- The (now deprecated) bash harvest — bundling both sides first, never
  writing the legacy checkout — captured three recovery refs:
  `harvest/dl-legacy/main` (converged insurance: legacy `main` == remote
  tip), `harvest/dl-legacy/head` (**the 374 unpushed commits**), and
  `harvest/dl-legacy/working-copy` (the dirty tree).
- Nothing *reported* "374"; the operator counted afterwards.

From the fixture analysis ([draft0.gpt6sol.md](/design/archive-migration/draft0.gpt6sol.md)):

- Re-running the same-label harvest **force-updated** the `working-copy`
  recovery ref (`d686612→3d496be`) despite an identical tree. Recovery refs
  must be append-only.
- Pre-harvest `--all` bundles **do not contain** the synthetic working-copy
  commit minted after bundling, nor ignored state.
- `jj git export` failure is warn-and-continue: jj-only work can silently
  miss the harvest.
- A transient `core.excludesFile` (via `GIT_CONFIG_*`, touching nothing in
  the legacy repo) provably excludes `.jj/` from the working-copy capture.

Verified jointly on production: the working-copy capture was **13,237 files,
13,233 of them the legacy `.jj/` index**; 16 `.beads/`/`.data/` paths are
*tracked* in dl's git — including `.beads/.beads-credential-key` in history
(commit `05190fb`) — so credential material already lives on GitHub, in the
archive clone, and in both bundles.

## The adopt design

### Surface

```text
archive adopt --legacy DIR --dest DIR --repo URL --branch main \
  --label dl-legacy [--exclude-from FILE] [--plan | --apply] [--json]
archive adopt verify --legacy DIR --dest DIR --label dl-legacy [--json]
```

`adopt` **plans by default** (gpt6sol's discipline; glm53's "narrate the
tail" is what a plan *is*). `--apply` transfers **source history and declared
dirty source files only** — never pnpm, never databases, never retirement.

### Semantics

1. **Preflight**: distinct realpaths; Git repo identified on each side; URL
   policy (declared-vs-actual table; never inherit the legacy remote's
   *names* — the archive's `origin` is the deployment contract, and for dl
   that contract is GitHub while legacy `origin` was Tangled); `health`
   preflight on both sides; submodule/LFS/writeability/backup-space checks.
   **Blocking condition**: a functioning legacy `.jj` with unexported
   revisions — warn-and-continue is how work goes missing; the operator pins
   or exports first.
2. **Exclusions**: never harvest `.git/`/`.jj/` internals into a
   working-copy commit (the 13,233-file lesson); respect `.gitignore`; accept
   `--exclude-from`; **report tracked files that exclusions cannot hide**
   (the `.beads`/`.data` case — ignoring now does not undo history); stop on
   unexplained private/transient files in the proposed tree. Prefer an
   explicit manifest over a universal database blacklist.
3. **Append-only recovery refs**: `harvest/<label>/{branch|head|working-copy}`
   may be reused only when OID/tree identity matches an unchanged source;
   differing work mints a **new** name (`working-copy-<parent>-<tree>`).
   Never `git push +` over a recovery ref. Check the namespace before
   writing anything — bundle or ref.
4. **Custody**: private, collision-resistant bundles **with checksums**
   before any write; then a **post-import** bundle so the synthetic
   working-copy commit is itself covered. `git add` failures are fatal, not
   `|| true`. Deterministic dirty-tree snapshot (parent + tree identity).
5. **The headline report**: the plan/apply output leads with the
   justification numbers — **"N unpushed commits rescued"** (`remote..HEAD`),
   branches captured, dirty files captured — then the *left-behind* report:
   ignored state files with exact copy commands (informational, never
   automatic), tracked runtime/credential material flagged for privacy
   review, bundle paths with verification results. The number that justifies
   the migration must never be something the operator counts by hand.
6. **Permission separation**: import ≠ publish ≠ retire. No automatic or
   wildcard push of recovery refs. Publishing is a separate, explicit action
   gated on the secrets review (the credential key makes this concrete).
   `verify` compares source fingerprints against archive refs, validates
   bundles, and produces a **retirement preflight** — outstanding jj-only
   revisions, ignored state, unmoved files, live shim target, worktree
   conflicts — as unresolved items, never executing deletion.
7. **Labels**: playbook refreshes use `NAME` (`dl-git`); migration harvests
   use `NAME-legacy`; re-runs are idempotent by content identity (semantics
   3), not by timestamp minting.

### The manual tail (README-worthy sequence)

1. **Inventory and hold**: stop writers; record status/branches/remotes/HEAD/
   stashes; audit tracked DB/credential paths; consistent backups of live
   databases (bundles are not runtime backups).
2. **Prepare the archive**: `health` if it exists; else
   `refresh --update false` + `health`. URL mismatch is a review gate.
3. **Import**: `adopt --apply` (or today: the deprecated script with the
   transient-exclusion workaround) — never re-run into a populated label.
4. **Verify**: `adopt verify`; compare refs and trees; fail the handoff on
   unexpected `.jj`, secrets, databases, or missing files.
5. **Select the deployment line deliberately**: source preservation does not
   decide whether `main` stays the runnable line — the operator does.
6. **Move runtime, then state, then the shim**: run `dl.src.pb`
   (`USERMODE=True`); confirm the shim's *target* (`readlink -f`), not just
   `command -v dl`; roll back with `cd "$LEGACY" && pnpm link --global`.
7. **Retire deliberately**: observation period, rename/park, dispose under
   explicit retention policy. Generating the `repo` symlink is not
   authorization to delete `~/src/dl`.

## Open questions (merged)

- A valid legacy `.jj` with conflicted unexportable heads: block until
  pinned/resolved — is that the acceptable default?
- Tracked runtime state (`.data/*.db-wal`, `.beads/`): history purge/rotation
  is an owner decision; does publication require that review first? (The
  credential key says yes.)
- Deployment workspace: adopt must not bake in the main-worktree contract;
  the [premise wave](/design/archive-deployment-premise/draft0.glm53.md)
  owns that decision.
- Backup custody: local bundles + source retention, or verified off-host
  copy required before retirement?
- Which remote is the deployment contract for dl — GitHub or Tangled — and
  when is an opt-in publish of audited recovery refs appropriate?

## README flagship

The final section of [`archive/README.md`](/archive/README.md) should be
"migrate a standalone checkout," telling the dl story with the 374-commit
rescue as the opening line. The tool's value proposition is invisible until
the moment it saves a checkout; that moment should be the front page.

## Cross-comparison of the sources

**draft0.glm53.md** (production walkthrough): strengths — the live evidence
and its headline (374 rescued commits), the quantified `.jj` sweep, the
"report the number" requirement, label taxonomy, README framing; weaknesses —
never inspected what the captured trees *contained* (missed tracked
credential material), missed the Tangled origin, framed re-run hazard as
duplicate noise rather than ref mutation, no fixture isolation.
Characterization: the narrative and product-sense draft.

**draft0.gpt6sol.md** (fixture analysis): strengths — append-only recovery
semantics, plan/apply + verify permission separation, bundle blind spots,
jj-export warn-and-continue, tested exclusion workaround, staged-order proof;
weaknesses — no production run, so no rescue-count evidence; denser and less
narrative; buries the reporting/README value. Characterization: the safety
engineering draft.

They disagree in emphasis, not substance: "compose and narrate" versus
"plan-first with separate permissions" resolve into plan-by-default. The
synthesis takes gpt6sol's safety architecture as the skeleton and glm53's
reporting, labels, and flagship framing as the contract with the human.
