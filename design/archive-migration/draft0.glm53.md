---
type: Design
title: Standalone-to-archive migration — dl as the flagship walkthrough
description: Migrating a standalone working checkout (~/src/dl) into compfuzor's archive lane is THE core workflow; performed live 2026-09-27 with the archive/ toolkit, rescuing 374 unpushed commits and exposing concrete toolkit gaps.
resource: /design/archive-migration/draft0.glm53.md
tags: [compfuzor, archive, migration, dl, jj]
status: draft
generated: { by: model:glm53, at: 2026-09-27 }
stale_after: 2026-11-27
sources:
  - id: walkthrough
    resource: /design/archive-migration/draft0.glm53.md#walkthrough
    title: live migration performed 2026-09-27 (this document)
  - id: harvest-legacy
    resource: /script/harvest-legacy-repo.sh
    title: legacy harvest script (bash, outside the toolkit)
  - id: toolkit
    resource: /archive/README.md
    title: archive/ jj toolkit command catalog
  - id: dl-playbook
    resource: /dl.src.pb
    title: dl deployment playbook (archive lane)
---

# Standalone-to-archive migration — dl as the flagship walkthrough

## What is up

Compfuzor's archive premise wants one canonical jj checkout per upstream at
`~/archive/<org>/<repo>`, deployments carrying only links. But the world is
full of **standalone working checkouts** created before that lane existed (or
by hand): `~/src/<repo>` clones with local branches, detached heads, dirty
trees, unpushed commits, runtime state, and globally linked shims. Moving them
into the archive **without losing anything** is the core problem this
toolchain exists to solve — and the moment most likely to destroy work if we
get it wrong.

`dl` is the perfect flagship specimen: it is standalone at `~/src/dl`
(detached HEAD, `main` branch, remote named `github` not `origin`, an
experimental untracked `.jj/`, gitignored runtime DBs, pnpm global shim),
it is the primary user of the very archive convention it is migrating into,
and [`dl.src.pb`](/dl.src.pb) now exists to manage the destination state.

On 2026-09-27 I performed the safe parts of this migration live with the
[`archive/`](/archive/README.md) toolkit. This draft records the walkthrough,
the evidence, and the gaps it exposed.

## Walkthrough {#walkthrough}

### 1. Create the canonical archive (toolkit `refresh`)

```sh
node archive/src/repo-jj-archive.ts refresh --json \
  --dest ~/archive/rektide/dl \
  --repo https://github.com/rektide/dl --remote origin --branch main \
  --label dl-git
# {"changed":true,"notices":[{"kind":"notice","message":"cloned jj-colocated
#   archive /home/rektide/archive/rektide/dl"},
#  {"kind":"bookmark-created","name":"main","target":"e9c7c40…"}]}
```

Fresh jj-colocated clone at the house path; `main` tracked at the remote tip.

### 2. Harvest the legacy checkout (nothing in it is touched)

```sh
./script/harvest-legacy-repo.sh ~/src/dl ~/archive/rektide/dl --label dl-legacy
# harvest: safety bundles written to /home/rektide/archive/rektide/
# harvest: branch  main -> harvest/dl-legacy/main
# harvest: head     c2ed9631… -> harvest/dl-legacy/head
# harvest: worktree f34658c7… -> harvest/dl-legacy/working-copy
# harvest: done (3 refs).
```

Safety first: both sides are `git bundle`d before any ref moves; the legacy
checkout is only ever *read*. Three captures landed as archive bookmarks:

- **`harvest/dl-legacy/head` — 374 unpushed commits.** The legacy detached
  HEAD sat on a chain (`github/main..HEAD` = 374 commits: Effect v4 workflow
  design, Model B campaign research, …) that existed **nowhere else**. Without
  this harvest, retiring the checkout would have orphaned months of history.
  This single fact is the strongest argument for the whole workflow.
- `harvest/dl-legacy/main` — converged insurance: legacy `main` ==
  `github/main` == archive `main` (e9c7c40), so this capture is a no-op
  today, and that is the correct cheap default.
- `harvest/dl-legacy/working-copy` — the dirty tree. See gap 1.

### 3. Verify with the toolkit itself

```sh
node archive/src/repo-jj-archive.ts health --dest ~/archive/rektide/dl
# Visible heads OK; no conflicted bookmarks
```

The preflight from the ghost-head incident, dogfooded on the fresh archive.

### 4. The deliberate manual tail (not yet performed)

1. `cd ~/archive/rektide/dl && pnpm install && pnpm link --global` — repoint
   the `dl` shim at the managed checkout.
2. Runtime state: `facts.db`/`wf.db` are gitignored, so harvest correctly did
   **not** capture them — which also means they do **not** migrate. Copy them
   from `~/src/dl` if continuity is wanted, or start fresh.
3. Verify: `jj -R ~/archive/rektide/dl log -r 'bookmarks()'`, spot-check the
   harvest bookmarks against the bundles in `~/archive/rektide/*.bundle`.
4. Adopt [`dl.src.pb`](/dl.src.pb) for ongoing refresh/build/link management.
5. Only then retire `~/src/dl` — deliberately, by hand.

## Gaps the walkthrough exposed

1. **Working-copy harvest swept VCS internals.** The working-copy capture is
   13,237 files, of which **13,233 are the legacy `.jj/` index** — four files
   of real content buried under junk. Harvest must exclude `.git/`, `.jj/`
   (and probably `.DS_Store`-class noise) from working-copy capture. The
   signal-to-noise here is the strongest possible argument for fixing it.
2. **The harvest story lives outside the toolkit.** `harvest-legacy-repo.sh`
   is bash in `script/`, not a command of [`archive/`](/archive/README.md).
   The migration workflow spans two tools with different error styles. It
   should become toolkit subcommands (fine-grained steps: `adopt`, with
   `harvest` pieces reusable) — same treatment repo-jj-archive.ts got.
3. **Runtime state is silently invisible.** Gitignored DBs are correctly
   excluded from harvest, but the operator gets no report that state exists
   and will not travel. An `adopt` should list "ignored-but-present state
   files" (facts.db, wf.db, node_modules) and the exact copy command —
   informational, never automatic.
4. **No composed entry point.** The migration is 2 commands + 5 manual steps
   today, with the ordering discipline (bundle → harvest → verify → repoint →
   retire) living in the operator's head. `adopt` should compose
   clone/refresh + harvest + health and *print* the remaining manual steps,
   the way harvest-legacy prints its verify block.
5. **Label taxonomy is ad hoc.** `dl-git` (playbook NAME) vs `dl-legacy`
   (harvest label). Proposal: playbook refreshes always use `NAME`; migration
   harvests use `NAME-legacy`; re-harvests should reuse a deterministic label
   (today's timestamped default labels would mint duplicates on re-runs).
6. **Retirement is unassisted.** Correctly so — pruning is deliberate — but a
   `retire` preflight could *check* the preconditions (bundles exist, harvest
   refs present in archive, no unpushed commits left `legacy-remote..HEAD`)
   and print what it verified, leaving the deletion to the operator.
7. **This walkthrough belongs in the README.** The user-facing flagship
   example for `archive/README.md`: "migrate a standalone checkout" with the
   dl story (374 rescued commits included).

## Open questions

- Where does runtime state *belong*? A checkout-local `facts.db` ties state
  to a tree that refresh wants to move under us; XDG data dirs would decouple
  it. That is dl's own design question, but `adopt` should surface it rather
  than silently stranding state.
- Should harvest push its refs to a remote by default (disaster-proofing), or
  stay opt-in as today? Bundles already give local recovery; remote copies
  survive disk loss. Lean: keep opt-in, report the command.
- Unpushed-commit reporting: `harvest/dl-legacy/head` rescued 374 commits,
  but nothing *told* me "374" — I counted afterwards. `adopt` should count
  and report `remote..HEAD` explicitly; that number is the migration's
  justification, not a footnote.

## Cross-references

- [`/design/repo-jj-archive/incident-ghost-heads.glm53.md`](/design/repo-jj-archive/incident-ghost-heads.glm53.md) — the failure class `health`/`heal` guard against; adopt must run the same preflight.
- [`/design/repo-jj-archive/draft1.gpt6sol.md`](/design/repo-jj-archive/draft1.gpt6sol.md) — the toolkit rework this builds on.
- [`/design/archive-deployment-premise/draft0.glm53.md`](/design/archive-deployment-premise/draft0.glm53.md) — the archive premise; migration is its missing front door.
- [`/script/harvest-legacy-repo.sh`](/script/harvest-legacy-repo.sh) — current bash implementation; candidate for absorption.
- [`/dl.src.pb`](/dl.src.pb) — the destination-side management once migration completes.
