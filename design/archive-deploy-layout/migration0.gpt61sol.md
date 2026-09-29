---
type: ImplementationBrief
title: Migrate only deployment symlinks to the selected archive
description: Automatically replace the legacy deployment-to-archive alias with a dedicated colocated jj/Git workspace, without general symlink replacement.
tags: [archive, deployment, jj, git-worktree]
status: draft
generated: { by: 'model:openai/gpt-6.1-sol', at: '2026-09-29' }
sources:
  - resource: /design/archive-deploy-layout/diagnosis0.gpt61sol.md
    title: Confirmed legacy alias failure and disposable migration reproduction
  - resource: /archive/src/repository/deploy.ts
    title: Existing deployment admission boundary
---

# Accepted request

The operator asks to detect the old `repo` symlink to the archive and replace it
with the intended deployment workspace automatically. They explicitly narrow
the request to **repo/archive**, not arbitrary filesystem symlink reconciliation.
They confirm the existing **deploy CLI integration tests** as the regression seam.

# Boundary

- A replacement candidate is a final-component deployment symlink whose
  canonical target equals the selected, validated archive.
- Replace the link with the existing dedicated jj/Git workspace model, not
  another alias of the archive's main checkout.
- Preserve the archive, its files, its local work, and its other workspaces.
  Creating the new workspace can snapshot archive-main work once under existing
  jj semantics; this is not an archive reset.
- Leave unrelated and dangling links untouched and refused. Do not add generic
  symlink replacement, stale artifact pruning, or automatic repair of unrelated
  workspace registrations.
- Canonicalize the **intended destination** through its parent for this migration;
  following the final old link would incorrectly make every legitimate migration
  look like archive/workspace equality. Still reject a destination nested in the
  archive, including parent symlink aliases into it.
- Perform available archive, remote, branch, and nesting validation before
  removing the link. Recheck the candidate immediately before removal so a
  changed, unrelated entry is not deliberately deleted.
- A later creation failure must not trigger broad deletion of partial state.
  Investigate whether restoring the original link is possible when no new
  destination was created; do not hide the original failure.

# Validation

Use disposable repositories through the real deploy CLI. Establish the primary
failure before changing implementation, then verify:

1. A deployment alias to its archive becomes a distinct real workspace with
   `.jj/repo` and `.git` pointer files; the archive's contents survive.
2. A second deployment run is idempotent.
3. Unrelated/dangling links remain untouched and refused.
4. Symlinked archive roots and relative link targets compare by canonical identity.
5. Nested destinations, including aliased parents, remain refused.
6. Failed preflight leaves the old deployment link intact.
7. Existing jj-only child workspace colocation behavior remains supported.

Update the shipped single-file distribution as well as the source implementation.
Keep the new behavior documented in the toolkit README; the earlier diagnosis
remains a historical account of the pre-migration policy.

# Deployment scope

Implementing the behavior does not authorize running the live OpenCode playbook,
rebuilding its binary, changing its composed `OPENCODE_WORKING_DIR`, or restarting
the service. The user can exercise the corrected deployment flow deliberately.

Custom `GIT_DIR` exposure is a separate boundary: [`fs_repo.tasks`](/tasks/compfuzor/fs_repo.tasks)
still refuses an occupied `DIR/repo` exposure link unless it already targets the
custom workspace. Therefore the earlier diagnosis's alternative-path suggestion
does not bypass the old exposure alias. This implementation addresses the
reported default deployment path and does not widen that Ansible link policy.

# Cross-references

- [Original diagnosis](/design/archive-deploy-layout/diagnosis0.gpt61sol.md):
  records the exact live alias layout, pre-change refusal, and fixture verification
  that replacing only the old link makes dedicated workspace creation possible.
- [Deployment implementation](/archive/src/repository/deploy.ts): shared
  library operation behind both Compfuzor and the public CLI; the narrow migration
  belongs here rather than in an OpenCode-specific workaround.
- [Deployment task](/tasks/compfuzor/repo_jj_archive.tasks): already provides
  distinct archive and workspace paths, so the default task interface needs no
  new operator flag to use the corrected behavior.
- [Archive README](/archive/README.md): maintained explanation of archive versus
  deployment responsibilities and how to run the source/distributed CLI.
