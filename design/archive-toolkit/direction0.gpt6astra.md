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

## Read-only checks need a stronger execution boundary

Initial code review found that existing `preflight()` calls ordinary `jj log`
and `jj bookmark list` through the general runner. That is not sufficient
evidence for the README's no-mutation claim: colocated jj queries can snapshot
or import Git state. Before reusing health for custody, introduce and fixture-test
a genuinely read-only query mode against the installed jj CLI's documented
flags. Custody remote checks must follow the same rule. Keep this correction
separate from the mechanical directory reorganization so its behavioral effect
is reviewable.

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

# Custody contract checkpoint

Reviewed [Sol's custody contracts](/design/archive-toolkit/custody-contracts0.gpt6sol.md)
and approved these implementation decisions:

- Add `--path-review FILE` separately from candidate dispositions. Bind review
  to the exact manifest, path/mode/blob identities, and nonempty rationales.
  Explicitly acknowledge a lost index/worktree distinction when applicable.
  Approval is for local Git custody, never publication or retirement.
- Prefer one atomic compare-and-create transaction for the receipt and all new
  pins, after bundle sealing, empty-repository restoration, and object transfer.
  This deliberately strengthens the brief's receipt-first sequence. Support
  diagnosing and completing matching receipt/partial-pin states without ever
  replacing the receipt or overwriting conflicting refs.
- Absent-destination support remains a v1 goal, but requires a separately tested
  full-clone path after admission. A named blocker is acceptable in an incomplete
  implementation slice; it must not be presented as full v1 support.
- Inventory SHA-1 and SHA-256 formats; reject source/destination mismatch and
  any unproven jj format combination rather than assuming compatibility.
- Use raw Node Buffer adapters for byte-sensitive plumbing where appropriate;
  Effect supplies typed orchestration and the CLI, not lossy conversion of Git
  path/object streams into terminal text.

## Operator correction: reuse process execution

The operator explicitly rejected building a custom subprocess runtime. Use
Effect's process execution facilities if available; otherwise use `tinyexec`.
Git remains the installed executable responsible for object, bundle, and ref
semantics. Private staging means a temporary Git repository, not a replacement
Git implementation. Keep only concrete command arguments, environment policy,
and result decoding in project helpers; do not build an injectable general
process framework. The first custom runner was checkpointed, found to have no
callers, and removed in a separate corrective commit rather than adopted as a
foundation.

# Cross-references

- [Custody brief](/design/archive-migration/brief0.gpt6sol.md): the detailed
  admission, inventory, receipt, bundle, transaction, and acceptance contract.
- [Governing custody design](/design/archive-migration/draft0-syn2.gpt6sol.md):
  explains the separation between custody, deployment, and retirement.
- [Archive README](/archive/README.md): current commands, refresh behavior, and
  the Ansible result protocol that this expansion must preserve.
- [Custody contracts](/design/archive-toolkit/custody-contracts0.gpt6sol.md):
  module seams, privacy review, immutable retry, and acceptance ownership.
