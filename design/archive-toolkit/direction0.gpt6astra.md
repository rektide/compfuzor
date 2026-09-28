---
type: ImplementationDirection
title: Archive toolkit — an independent library with a Compfuzor adapter
description: Scope, architectural boundaries, compatibility commitments, and implementation checkpoints for the Effect CLI expansion.
status: draft
generated: { by: model:gpt6astra, at: 2026-09-27 }
sources:
  - resource: /design/archive-migration/brief0.gpt6sol.md
    title: Git custody implementation brief
  - resource: /archive/README.md
    title: Existing archive toolkit contract
---

# Situation and destination

The existing archive runner is more than an Ansible helper, but its CLI currently
contains operations and its modules occupy a flat directory. The operator asks
for a broader, well-structured subproject using Effect and its CLI implementation
in `~/archive/Effect-TS/effect`, while keeping Compfuzor working through its
existing task and a dependency-inclusive single-file distribution.

This work combines two distinct changes: making the current operations reusable,
and adding the receipt-driven Git custody capability specified by the
[latest brief](/design/archive-migration/brief0.gpt6sol.md). Neither grants
permission to migrate a production checkout, deploy its recovered history,
publish refs, prune artifacts, or retire a source directory.

# Architectural decisions

- Keep `archive/` as the subproject; do not introduce a new product name or npm
  publishing requirement just to reorganize it.
- Group implementation by domain: `repository/` for ordinary checkout operations,
  `recovery/` for jj recovery and explicit repair, `custody/` for cross-repository
  adoption, `cli/` for parsing/rendering, and `runtime/` for execution boundaries.
- Domain operations return data, not terminal output. Compfuzor is a consumer of
  the refresh result, not a dependency of the repository or custody domains.
- Preserve the existing Promise library while introducing Effect at deliberate
  boundaries. Verify the installed upstream generation before adopting service,
  error, or CLI APIs; Effect 3 examples are not evidence for Effect 4 APIs.
- Do not create an abstract universal Git/jj backend. Git object custody and jj
  worktree management have different guarantees and mutation permissions.
- Adoption never invokes refresh on an existing destination. Source reads,
  isolated object construction, and destination ref installation must remain
  distinguishable in both code and tests.
- A receipt records an expected transfer. Only independent verification can
  report custody complete. Verification never reports permission to delete.

# Proposed operator surface

Keep the existing top-level commands, rather than making users discover a new
nesting scheme while implementation changes underneath them:

| Area | Commands | Permission boundary |
|---|---|---|
| Inspection | `health`, `remotes`, `self` | Read-only unless an explicit mutation flag is supplied |
| Routine checkout management | `refresh`, `fetch`, `snapshot` | May snapshot/import or update the active archive checkout |
| Recovery and repair | `harvest`, `heal --yes` | Explicit recovery pinning or jj-state replacement |
| Source custody | `adopt`, `adopt --apply`, `verify-adoption` | Plan; then explicit immutable import; then independent verification |
| CLI assistance | help, version, completion | Never accidentally interpreted as refresh |

The command name `adopt` means cross-checkout custody, not the existing refresh
step that initializes jj metadata in a Git checkout. Help and docs must make that
distinction visible. No deployment/workspace-selection commands are introduced.

# Compatibility is an executable contract

[`repo_jj_archive.tasks`](/tasks/compfuzor/repo_jj_archive.tasks) retains its
launcher and `refresh --json` argv. Success yields exactly one JSON line with
`changed` and `notices`; failures have nonzero exit status, stderr diagnostics,
and no partial stdout JSON. Preserve flag-only legacy refresh and its branch
spelling `--version`, without stealing ordinary root help/version/completion.

Source development runs TypeScript directly. The committed `.mjs` artifact is
distribution only and must run outside this checkout without `node_modules`.
Changing CLI dependencies requires updating the launcher's source availability
checks; preserving its filesystem path matters more than preserving stale
Gunshi-specific detection code. Node and external Git/jj executables remain
runtime prerequisites, not dependencies that JavaScript bundling can eliminate.

# Implementation checkpoints and delegation

1. GX separates existing operations without changing their behavior. FX finds
   recent local Effect CLI precedents and independently audits compatibility
   coverage. Sol Medium resolves custody contracts and admission ambiguities.
2. Parent reviews actual upstream API evidence and interfaces, then authorizes
   the Effect CLI/build slice and parallel custody inventory/artifact slices.
   Most implementation goes to GX; Sol Medium owns the critical immutable
   transaction/retry coordination. At most two FX workers run concurrently.
3. Parent reviews the emerging public surface in-band with the operator and
   examines safety seams before apply is exposed as successful functionality.
4. Independent review and disposable fixtures cover source immutability,
   restored bundle closure, collisions/retries, JSON purity, launcher fallback,
   and standalone distribution. Commit each coherent slice, including research.

Tests are not permission to exercise production migration. Existing unrelated
working-copy changes remain outside these commits.

# Cross-references

- [Custody brief](/design/archive-migration/brief0.gpt6sol.md): the detailed
  admission, inventory, receipt, bundle, transaction, and acceptance contract.
- [Governing custody design](/design/archive-migration/draft0-syn2.gpt6sol.md):
  explains the separation between custody, deployment, and retirement.
- [Archive README](/archive/README.md): current commands, refresh behavior, and
  the Ansible result protocol that this expansion must preserve.
