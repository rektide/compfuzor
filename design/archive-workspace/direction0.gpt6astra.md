---
type: DesignDirection
title: Archive-backed workspaces — conversion and regular update as one workflow
description: Operator intent, update policy stages, and the structural conversion question that replaces custody as the primary Compfuzor workflow.
status: draft
generated: { by: model:gpt6astra, at: 2026-09-28 }
sources:
  - resource: /design/archive-deployment-premise/draft0.glm53.md
    title: Earlier dedicated-workspace intent
  - resource: /design/archive-workspace/conversion0.gpt6luna.md
    title: First workspace-conversion fixtures
  - resource: /archive/README.md
    title: Implemented toolkit, not the complete desired workspace workflow
---

# The job we are building toward

Compfuzor used to own standalone Git checkouts. Its normal repository operation
should establish a canonical archive-backed jj repository, turn the old checkout
into a workspace of that repository, and subsequently update that workspace.
The archive root's own working-copy position must not determine deployment state.

The earlier custody implementation preserves selected work in an existing
archive, but does not perform this structural conversion. It is useful machinery
for some transfers, not the governing user experience. Do not make the ordinary
upgrade depend on a manual receipt/review ceremony merely because that machinery
exists. Keeping a whole repository need not require deciding which history is
available upstream; that question belongs to update/bookmark policy.

# User-directed update policy

This is a sequence with independent controls, not unrelated case-specific tools:

1. **Dirty work:** fail by default. Offer an explicit mode to save it as a
   revision and bookmark it. Automatic jj snapshots must not silently redefine
   unfinished work as clean, operator-approved history.
2. **Upstream evidence and bookmark decision:** determine the actual upstream
   target without moving the workspace first. By default, bookmark a starting
   revision unavailable upstream, then proceed; allow a stricter refusal policy.
   A dirty snapshot normally needs that local protection too, not redundant pins.
3. **Advancement:** proactively update to latest upstream by default. Distinguish
   a real fast-forward from preserving a local-only tip and moving the workspace
   to upstream. Do not call the latter a merge or silently rewrite local branches.
4. **Report:** retain starting revision, saved-work/bookmark identities, selected
   upstream remote/ref/OID, resulting workspace state, and action classification.

Modes should package these controls, while individual overrides remain possible.
Provisional parent proposal, not an implemented or user-approved spelling:

| Preset | Dirty | Local-only revision | Advance |
|---|---|---|---|
| Update (default) | Fail | Bookmark | Latest upstream |
| Strict | Fail | Fail | Fast-forward only |
| Save and update | Save + bookmark | Bookmark | Latest upstream |

A failed preservation step prevents advancement. “Available upstream” still needs
a concrete ref/remote scope and freshness rule; locally recorded remote-tracking
refs alone are not current server evidence. A named mode must not conceal this.

# Structural conversion should preserve the directory, not reconstruct its state

The prime case is an old standalone application Git checkout. An already shared
jj development hub with many external workspaces is a distinct complication,
not evidence that the prime case necessarily requires those migration steps.

Preserve the existing checkout's ordinary files, including ignored/runtime state.
Prefer retaining the original directory and file inodes over copying that state
out and back. Do not turn this requirement into an unsolicited live-database
backup system; quiescing writers is still necessary during a structural change.

The user explicitly permits a version-sensitive approach: temporarily rename the
original directory, let jj create correct workspace metadata at its intended
path, then restore the original tree with that metadata. Investigate this
concretely against local jj source and fixtures before choosing a copy-based
algorithm or writing a product implementation.

The first [conversion study](/design/archive-workspace/conversion0.gpt6luna.md)
proves that `workspace add --colocate` creates the desired shared repository
relationship and that later updates can leave archive-root `@` alone. Its
whole-directory move plus file-copy sequence does not yet establish the preferred
original-directory-preserving transition. A second fixture study is testing it.

# Gates before implementation

- Establish the supported or deliberately version-sensitive conversion mechanics,
  including metadata paths, same-filesystem assumptions and interrupted states.
- Agree how an already populated archive is handled. `workspace add` does not
  merge independent repositories; URL equality alone cannot decide the transfer.
- Define dirty state for plain Git and jj workspaces without trusting a pinned
  jj view to describe unsnapshotted files or invoking executable Git helpers.
- Resolve upstream identity and advancement semantics, then expose the policy
  pipeline through the single Compfuzor-facing operation and structured result.

This document records direction and open decisions. It neither authorizes a real
checkout conversion nor claims the existing `refresh` implements these policies.
