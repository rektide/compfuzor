---
type: Design
title: jj archive toolkit — composable commands and explicit repair
description: Landed command surface, safety boundaries and Ansible integration for the jj archive runner.
resource: /design/repo-jj-archive/draft1.gpt6sol.md
tags: [compfuzor, archive, jj, toolkit]
status: draft
generated: { by: model:gpt6sol, at: 2026-09-27 }
sources:
  - id: incident
    resource: /design/repo-jj-archive/incident-ghost-heads.glm53.md
    title: Ghost-head incident and lessons
  - id: subsystem
    resource: /design/repo-jj-archive/draft0.gpt6sol.md
    title: Existing archive refresh safety contract
  - id: scaffold
    resource: /design/repo-jj-archive/scaffold0.glm53max.md
    title: Scaffold and dual-path launcher
---

# jj archive toolkit — composable commands and explicit repair

## What is up

Compfuzor's archive lane started as one JSON-emitting runner acting on the
archive's main worktree. The [ghost-head incident](/design/repo-jj-archive/incident-ghost-heads.glm53.md)
exposed an opaque failure before fetch and made deliberate recovery important.
The operator now wants a general, human-facing jj toolkit with granular steps
**and** an unchanged Ansible convergence path. This slice decomposes the runner
without taking on the [workspace/per-bookmark-sync premise](/design/archive-deployment-premise/draft0.glm53.md).

## Surface and modules

The [front page](/archive/README.md#commands) lists exact flags and examples.
Gunshi commands: `health`, `snapshot`, `harvest`, `remotes`, `fetch`, `refresh`,
`heal`, `self`, plus completion plugin's `complete`. `refresh` composes the
existing safety sequence; `fetch` is deliberately narrower and does **not**
move the selected local base. The flag-only legacy call aliases `refresh
--json`; legacy `--version` becomes `--branch` because Gunshi reserves
`--version` globally. This small adapter is preferable to keeping two distinct
refresh implementations.

| Module | Ownership |
|---|---|
| [`repo-jj-archive.ts`](/archive/src/repo-jj-archive.ts) | Gunshi definitions, help, human/JSON output, compatibility argv adapter. |
| [`jj.ts`](/archive/src/jj.ts) | Promisified argv-only jj invocation, structured `JjError`, templates/ref and revision queries. |
| [`health.ts`](/archive/src/health.ts) | Materialize `visible_heads()` and report conflicted bookmarks/ghost IDs. |
| [`remotes.ts`](/archive/src/remotes.ts) | Validate declarations, compare actual URLs, render differences, explicit reconcile. |
| [`harvest.ts`](/archive/src/harvest.ts) | Stable duplicate, dated recovery bookmark, `recoveryCovered` repeat-run check. |
| [`refresh.ts`](/archive/src/refresh.ts) | Clone/adopt and ordered convergence flow; returns result, does not own output. |
| [`heal.ts`](/archive/src/heal.ts), [`self.ts`](/archive/src/self.ts) | Opt-in re-adoption with retained backup; optional standard compfuzor checkout detection/fetch. |

The duplication of the pre-fetch snapshot/freeze sequence between the small
`fetch` command and `refresh` is currently bounded; a shared preparation
primitive is worth extracting when that sequence gets another consumer, not
when it would obscure the explicit ordering in the principal flow.

## Hardening and Ansible decision

- `visible_heads()` is forced before any `heads(all())` operation; its missing
  object diagnostic is converted to an actionable error with the missing ID,
  conflicted-bookmark guidance, and the opt-in `heal` command. `health` runs
  this probe without refresh. The test quarantines a loose object from a bare
  view head in a disposable Git ODB, removes any fixture-only keep ref, and
  verifies recovery. We intentionally do **not** pretend re-adoption can
  recover jj-only history: the old `.jj` remains as a dated backup.
- Existing URL mismatch now fails before fetch/harvest with a declared/actual
  table and shell-safe reconcile invocation. Missing remote names are added by
  `refresh` as before; `remotes --reconcile` applies both adds and URL changes.
  No remote URL rewrite is the default. Opt-in `refresh --reconcile-remotes`
  supports deliberate one-shot Ansible convergence.
- The [task](/tasks/compfuzor/repo_jj_archive.tasks) now invokes `refresh
  --json` explicitly. `GIT_REMOTE_FIX=true` passes the opt-in URL reconciliation
  flag; absent/false preserves fail-loud behavior. The launcher resolves src
  first when its CLI modules are installed, committed bundle otherwise, and never relies on `self` detecting an
  archive compfuzor checkout. Gunshi's default header and validation output
  were disabled, so success is one JSON line and errors go to stderr.
- `--update false` still snapshots and checks remotes; it skips fetch and
  selected-base/worktree reconciliation for a populated archive. The old
  harvest, untrack, fetch, base preservation and merge ordering remains from
  [draft0](/design/repo-jj-archive/draft0.gpt6sol.md).

## Boundaries and questions

- The main archive checkout still matters and `refresh` may merge into it.
  Dedicated deployment workspaces, per-bookmark push/pull/divergence planning,
  push policies, and the `dl` playbook are **not implemented** here. They
  should be treated as distinct follow-on decisions, not silently added to
  this refresh path.
- `visible_heads()` stops on the first unreadable object. The error names
  missing ID(s) jj returns; if several unrelated ghost heads exist, another
  preflight after resolving/re-adopting may expose a further ID. A full view
  forensic inspector or GC policy needs a separate design and primary-source
  verification. A Git ref that itself points at a missing object also needs
  manual repair: replacing `.jj` cannot repair the Git ODB.
- `fetch` alone freezes tracked local refs and deliberately leaves branch
  movement/retracking to `refresh`. Should a future operator surface expose
  `prepare-fetch`/`track` separately, or define a self-contained multi-remote
  fetch transaction? The present command is safe but does not promise full
  convergence alone.
- `heal` creates a backup within the checkout and reimports whatever Git refs
  remain. Backups are not automatically pruned; disaster recovery and
  inaccessible Git objects are outside the toolkit's repair promise.

## Verification and cross-references

- [`tests/integration/repo_jj_archive.test.py`](/tests/integration/repo_jj_archive.test.py)
  covers existing Ansible and jj behavior, CLI/legacy equivalence, ghost
  preflight and explicit re-adoption, remote mismatch/reconciliation including
  the Ansible opt-in, and independent `self`/`snapshot`/`fetch` commands.
- [Incident evidence](/design/repo-jj-archive/incident-ghost-heads.glm53.md)
  explains why a view head outside Git's protected refs can be pruned.
- [Deployment premise](/design/archive-deployment-premise/draft0.glm53.md)
  remains the next design gate: workspaces and per-bookmark sync should not
  inherit this slice's main-worktree assumption unquestioned.
