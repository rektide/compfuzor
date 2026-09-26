---
type: Design
title: Archive deployment premise — workspace vs archive main working copy
description: The ARCHIVE_DOWNLOAD repo surface symlinks deployments at the archive's main working copy; the intended premise is a dedicated jj workspace so the archive checkout state never matters.
resource: /design/archive-deployment-premise/draft0.glm53.md
tags: [compfuzor, archive, jj, repo, deployment]
status: draft
generated: { by: model:glm53, at: 2026-09-26 }
stale_after: 2026-11-26
sources:
  - id: runner
    resource: /script/repo-jj-archive.ts
    title: repo-jj-archive refresh runner
  - id: includes
    resource: /tasks/compfuzor.includes
    title: repo_jj_archive / repo_git task gating
  - id: opencode-pb
    resource: /opencode.src.pb
    title: primary archive-mode consumer (INSTANCE=git)
---

# Archive deployment premise — workspace vs archive main working copy

## What is up

`ARCHIVE_DOWNLOAD: true` ([`vars/common.yaml`](/vars/common.yaml)) routes a
playbook's `REPO` through [`repo_jj_archive.tasks`](/tasks/compfuzor/repo_jj_archive.tasks)
→ [`script/repo-jj-archive.ts`](/script/repo-jj-archive.ts), with
`REPO_DIR` resolving to `~/archive/<org>/<repo>` and the deployment dir getting
`repo -> REPO_DIR` ([`fs_repo.tasks`](/tasks/compfuzor/fs_repo.tasks)). The
runner then operates **directly on the archive repo's main working copy**:

- `jj status` snapshots the main checkout;
- a dirty `@` is harvested to `harvest/<label>/working-copy-*`;
- local `working` (or the `GIT_VERSION` branch) is force-set to the selected
  remote tip and tracked;
- `@` reconciliation can `jj new @ base` a **merge onto the main working copy**,
  leaving conflicts for the operator.

The operator's stated intent (2026-09-26, after the opencode.src.pb review):

> are we symlinking to ~/archive/anomalyco/opencode? nuts. **i had intended for
> us to have a jj workspace!** big whoops. […] state of ~/a/a/opencode should
> not matter.

That is: the deployment's repo surface should be a **dedicated jj workspace**
of the archive repo, and the archive main working copy's state should be
irrelevant to every deployment. Today the opposite is load-bearing: the runner
mutates the main copy, and a parked `@` on an unrelated line (opencode's
`grace-20260923`) forced merge/conflict behavior on refresh.

## Evidence from the opencode deployment (2026-09-26)

- Archive `~/archive/anomalyco/opencode` is colocated git+jj, created
  2026-02-13, trunk for ~60 workspaces (incl. `~/src/opencode-working`,
  `v1`, `v2`, `dev`, dozens of `opencode-*` variants).
- Local `working` = `working-20260923` = `960ed25d` ("record 2026-09-23/24
  composition friction report"); rektide's remote `working` was still the Aug-13
  tip `9306ac69` (locally kept as `working-20260813`). Running the playbook
  before pushing would have force-rewound `working` a month (harvest bookmark
  preserving the tip) and merged the grace line into `@`.
- rektide was nearly empty: a fleet push added ~150 bookmarks + ~700 tags;
  `working` needed `--allow-empty-description` (empty undescribed commit
  `04319825` in range), and conflicted tips (`explicit-port-20260817`,
  `jj-vcs-rektide*`, `watchman*`) were refused — the desired "detect conflicts
  and bail" behavior fell out of `--all` for free.
- Cleanup fallout: dangling `/opt/opencode-git` + `/opt/opencode-dev` symlinks
  from a `/tmp` instance experiment (removed; nothing in compfuzor mints
  `/opt/<name>` for src deployments), and a 20-day hung
  `jj git push -b main` from the bitblaster era (killed).

## Direction: intelligent per-bookmark sync

The operator's sync policy, replacing the runner's blanket moves:

- **Per-bookmark push/pull decisions** — no wholesale `bookmark untrack` of
  every tracked ref before fetch. Untracking exists so fetch cannot move local
  tips; a per-bookmark comparison (local vs remote target) can decide
  push / pull / diverged without detaching tracking globally.
- **Diverged ⇒ bail loudly.** If local and remote tips have genuinely diverged
  (neither is ancestor of the other), fail that bookmark with a notice instead
  of force-resolving (today: harvest + force-`set -B`, which rewinds silently
  from the operator's perspective).
- **Push targets with graceful degradation:** push to `rektide` and `tngl`
  where declared; if neither is available, fall back to `upstream`; accept
  push failures for remotes that are not ours. compfuzor never pushed before —
  this adds an explicit, bounded push phase.
- **The archive main working copy becomes just another workspace** — or better,
  never touched by tooling at all.

## Options for the repo surface

- **A. Workspace per deployment.** `REPO_LINK_DIR` links to a jj workspace
  (e.g. `~/src/<label>-archive` or a workspace under the deployment dir)
  created/refreshed by the runner and parked at the `GIT_VERSION` tip. The
  archive main copy is never mutated. Cost: workspaces accumulate; runner grows
  workspace lifecycle (`jj workspace add`, stale-workspace detection).
- **B. Ref-only runner + internal scratch workspace.** Runner does bookmark/ref
  operations only; anything needing a working copy (harvest diffs, checkout)
  happens in a private workspace it owns. Main copy untouched; deployment still
  symlinks at the archive for read paths. Cost: two surfaces to reason about.
- **C. Status quo + guardrails.** Keep main-copy operation; document that the
  archive checkout must stay parked on the selected branch; keep harvest
  safety nets. Cheapest, preserves the exact behavior that surprised us.

## Open questions

- Who owns build workspaces? `opencode.src.pb` builds from the manually composed
  `~/src/opencode-working` — under option A, is that composition what the
  deployment should own/refresh, or does it stay operator territory?
- Does `GIT_VERSION working@rektide` remain a *bookmark* contract, or does a
  workspace-per-deployment world check out the tip into the workspace `@` and
  drop local bookmark force-moves entirely?
- Interaction with `repo_git.tasks` for `REPOS` (supplemental clones) and with
  `GIT_FORCE`/`GIT_DEPTH` semantics under workspaces.
- Push phase placement: playbook run (opt-in `REPO_PUSH`?) vs separate operator
  command the playbook only notices.

## Addendum: what the 2026-09-26 fleet push proved

The rektide/tngl fleet push (≈1270 refs landed on rektide, 1261 on tngl)
exercised every failure mode the intelligent sync must handle:

- **Stale remote-tracking ⇒ false plans.** The local view of rektide was weeks
  old, so `--dry-run`/`--all` planned ~150 bookmarks as `[add]` that the fork
  already held at pre-rebase targets. Seven pushes failed with
  "unexpectedly moved on the remote (reason: stale info)". A sync that fetches
  (with `git.abandon-unreachable-commits=false`) *before* planning would have
  computed the real per-bookmark deltas.
- **Rebase-refresh divergence.** Tracking a remote bookmark whose target shares
  no ancestry with local (the refresh workflow rebases lines onto new bases)
  turns the local bookmark into a jj *conflict* — jj's own guard against
  clobbering unknown remote state. That is the desired bail; resolution was a
  deliberate operator decision ("local tips win", old tips already preserved
  under dated names on both sides).
- **Conflicted history blocks explicit pushes.** `working`'s range contains a
  conflicted intermediate (`b66b6537`, jj-vcs work resolved later) and an empty
  undescribed commit (`04319825`), so pushing it required both
  `--allow-conflicts` and `--allow-empty-description`. Per-bookmark push
  reporting should surface *why* (range-commit vs tip) rather than only naming
  the first offender.
- **Push targets behaved as specified.** rektide (primary) accepted the fleet;
  tngl accepted 1261 refs including everything the rektide run skipped for
  description reasons; conflicted/undescribed WIP tips
  (`explicit-port-20260817`, `jj-vcs-rektide*`, `watchman*`,
  `subagent-list-wip`, `watchman-design-wip0`) were refused per-bookmark and
  left local — conflicts bail, as intended.
- **Zombie pushes accumulate.** Two leftover `jj git push -b main` processes
  (Sep 6 and Sep 20, one suspended) were found holding nothing; killed. A
  sync tool that owns pushes should also surface/handle stale pushers.

## Cross-references

- [`opencode.src.pb`](/opencode.src.pb) — the consumer that surfaced this; its
  README already documents building from a composed workspace, not the
  deployment checkout.
- [`tasks/compfuzor/repo_git.tasks`](/tasks/compfuzor/repo_git.tasks) — the
  non-archive sibling; its `rev@remote` resolution (`working@rektide`) is the
  shared version selector.
- `/design/config-anneal/` — unrelated, but the pattern of "runner emits
  structured JSON notices for Ansible" established there is what a
  per-bookmark sync report should follow.
