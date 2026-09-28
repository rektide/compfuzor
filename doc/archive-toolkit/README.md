---
type: TopicDoc
title: Archive toolkit
description: Entry point for the repo-jj-archive toolkit — CLI contract, Node 26 transport, and custody operator/library guide.
resource: /doc/archive-toolkit/README.md
tags: [compfuzor, archive, jj, effect, cli]
status: stable
generated: { by: model:glm53, at: 2026-09-28 }
stale_after: 2027-01-28
sources:
  - id: operator-contract
    resource: /archive/README.md
    title: Archive toolkit operator contract
  - id: direction
    resource: /design/archive-toolkit/direction0.gpt6astra.md
    title: Implementation direction and accepted parser changes
  - id: compat-matrix
    resource: /design/archive-toolkit/compatibility-checks0.glm53.md
    title: Gunshi-era behavior matrix and test-gap analysis
---

# Archive toolkit

`repo-jj-archive` is compfuzor's jj toolkit for the `~/archive/<org>/<repo>`
source archives: small individually runnable operations (`health`, `snapshot`,
`harvest`, `remotes`, `fetch`, `heal`, `self`), a composed `refresh` for
Ansible, and tab-completion generation. The CLI is built on Effect
(`effect` + `@effect/platform-node`, pinned 4.0.0-rc.118); the operations
library underneath remains Promise-based — Effect was adopted at the CLI
boundary, not everywhere. This is a partial adoption by design, not a
completed Effect migration.

The operator-facing contract — commands, flags, refresh ordering, the
one-JSON-line Ansible protocol, launcher resolution — lives in
[`/archive/README.md`](/archive/README.md). This document is the doc-tree
entry point: it summarizes what is pinned and where the inquiry records live.
The launcher calls the selected entry's `runExecutable()` so native Node
signal handling can finish child-process teardown; `main()` remains the
importable Promise API.

## The CLI contract is executable

Two suites pin the surface; both run from disposable jj+Git fixtures and never
touch production archives:

- [`tests/integration/repo_jj_archive.test.py`](/tests/integration/repo_jj_archive.test.py)
  — the Ansible-behavior baseline (argv, JSON shape, diagnostics, launcher,
  bundle transport).
- [`tests/integration/archive_cli_contract.test.py`](/tests/integration/archive_cli_contract.test.py)
  — the command-line surface: failure purity (nonzero rc, empty stdout, one
  `repo-jj-archive:` stderr line), help/version/completion behavior, argv
  parsing semantics, legacy adapter rules, launcher resolution order, and
  bundle self-containment.
- [`archive/test/repository/cancellation.test.ts`](/archive/test/repository/cancellation.test.ts)
  — SIGINT/SIGTERM through the actual source entry, launcher, and an executable
  copied bundle; asserts empty stdout, a killed `jj` child, and no delayed
  child mutation.

Non-negotiable invariants: failures leave stdout empty (Ansible parses
stdout only when rc == 0); `refresh --json` success is exactly one JSON line;
the Ansible task path and JSON shape are unchanged by the Effect migration.

### Accepted native differences from the Gunshi era

Recorded in [`direction0.gpt6astra.md`](/design/archive-toolkit/direction0.gpt6astra.md)
after the migration review: native Effect help/error **wording** is not pinned
(only that the offending token is named on stderr), missing flags are reported
one at a time, duplicate flags are **first-wins**, unexpected positionals are
**rejected** (including after `--`), and root help wins over version in the
action precedence. What is pinned instead of Gunshi quirks: root `--version`
prints the toolkit version, and the native `--completions` action is not
stolen by the legacy flag-only refresh adapter. The legacy adapter itself
keeps working: flag-only invocation means `refresh --json`, `--version BRANCH`
spells `--branch BRANCH` under refresh, and `--` stops the adapter's scan.

## Completion coverage

| Shell | Source | Coverage |
|---|---|---|
| bash / zsh / fish | Effect CLI command-tree generator (same bytes as the native `--completions` action) | Full tree: subcommands and per-command flags |
| powershell | Static generator in the toolkit | **Subcommand names and global flags only** — not per-command flags; a documented coverage reduction, not parity |

## Custody: operator and library guide

[`custody.md`](/doc/archive-toolkit/custody.md) is the maintained guide to
`adopt` (read-only plan unless `--apply` is explicit), `verify-adoption`,
review inputs, supported cases, the private vault, and public library entry
points. Local existing-destination clean/dirty fixtures pass, but independent
safety review remains open. These commands are **not production signoff** or
retirement authorization. They do not publish refs or retire a source directory.

## Where the inquiry lives

[`design/archive-toolkit/`](/design/archive-toolkit/) holds the wave records:

- [`direction0.gpt6astra.md`](/design/archive-toolkit/direction0.gpt6astra.md) —
  scope, architectural boundaries, compatibility commitments, and the accepted
  parser changes; the governing document for what the tests may pin.
- [`compatibility-checks0.glm53.md`](/design/archive-toolkit/compatibility-checks0.glm53.md) —
  the Gunshi-era behavior matrix that motivated the contract suite (historical:
  its "current" columns describe the pre-migration CLI).
- [`effect-cli-references0.glm53.md`](/design/archive-toolkit/effect-cli-references0.glm53.md) —
  Effect CLI API eras (`effect/unstable/cli` vs `effect/cli`), local
  precedents, and the process-execution boundary decision.
- [`custody-contracts0.gpt6sol.md`](/design/archive-toolkit/custody-contracts0.gpt6sol.md)
  and [`core-review0.glm53.md`](/design/archive-toolkit/core-review0.glm53.md) —
  custody module seams and the still-open integration/safety review gate; CLI
  registration does not mean the gate has passed.

Older lineage (pre-Effect toolkit design): [`design/repo-jj-archive/`](/design/repo-jj-archive/),
including the [ghost-head incident](/design/repo-jj-archive/incident-ghost-heads.glm53.md);
the custody brief: [`design/archive-migration/brief0.gpt6sol.md`](/design/archive-migration/brief0.gpt6sol.md).

## Open items

- Bundle freshness is hand-maintained: rebuild (`pnpm build`) and commit the
  single-file `archive/repo-jj-archive.ts` with source changes; it may lag
  while source changes land. No rebuild-is-a-no-op test exists yet.
- The archive runner requires system Node 26, supplied by the Nodesource
  26.x `nodejs` package in [`nodesource.repo.pb`](/nodesource.repo.pb). The
  bundle contains all JavaScript dependencies but no Node binary, and does
  not support older Node versions. The root package engine range remains
  broader for other project tools; it is not the archive runner's runtime
  contract.
- The Node 26 runtime floor and signal behavior are exercised manually, not
  by suite.
- Custody production signoff awaits the final independent safety check and
  resolution of any resulting findings; fixture coverage is not signoff.
